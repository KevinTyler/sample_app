# Something the host sends to a set of guests: the invitation itself, an update,
# a reminder, or a cancellation notice.
#
# Idempotency, end to end:
# * Each send form carries a one-time `idempotency_key`; a double-submitted form or a
#   retried request finds the existing Message instead of creating a second one.
# * Deliveries are unique per (message, guest, channel), so re-running #dispatch! never
#   creates duplicates — it only fills in recipients that are missing.
# * Invitations additionally skip guests who already have a live invitation delivery from
#   an earlier message, unless the host explicitly asks to resend.
# * Each Delivery is claimed atomically before sending (see Delivery#deliver_now!).
class Message < ApplicationRecord
  KINDS = %w[invitation update reminder cancellation].freeze
  CHANNELS = %w[email sms].freeze
  STATUSES = %w[draft scheduled dispatched].freeze

  belongs_to :event
  belongs_to :author, class_name: "User", optional: true
  has_many :deliveries, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, length: { maximum: 64 }, uniqueness: { scope: :event_id }
  validates :subject, length: { maximum: 150 }
  validates :body, length: { maximum: 5000 }
  validates :subject, :body, presence: true, if: -> { kind.in?(%w[update reminder]) }
  validate :channels_supported
  validate :schedule_in_future, if: -> { status == "scheduled" }

  scope :due, -> { where(status: "scheduled").where(scheduled_for: ..Time.current) }
  scope :for_guests, -> { where(kind: %w[update reminder cancellation]) }

  def audience
    Audience.new(event, super || {})
  end

  def audience=(value)
    super(value.is_a?(Audience) ? value.to_h : value)
  end

  def channels
    Array(super).map(&:to_s) & CHANNELS
  end

  # Guests this message will go to if dispatched now (and can be reached on its channels).
  def recipients
    scope = audience.guests.and(reachable_guests)
    # Updates, reminders and cancellations only go to people who know about the event:
    # guests who were sent an invitation or who have responded.
    scope = scope.where.not(invited_at: nil).or(scope.where.not(rsvp_status: "pending")) unless kind == "invitation"
    if kind == "invitation" && !audience.resend?
      already = Delivery.joins(:message)
        .where(messages: { event_id: event_id, kind: "invitation" })
        .where(status: Delivery::LIVE_STATUSES)
        .select(:guest_id)
      scope = scope.where.not(id: already)
    end
    scope
  end

  # Creates any missing deliveries and enqueues them. Safe to call repeatedly.
  def dispatch!
    now = Time.current
    rows = recipients.to_a.flat_map do |guest|
      channels.filter_map do |channel|
        next unless (address = guest.address_for(channel))

        { message_id: id, guest_id: guest.id, channel: channel, recipient: address, status: "queued",
          created_at: now, updated_at: now }
      end
    end
    Delivery.insert_all(rows, unique_by: %i[message_id guest_id channel]) if rows.any?

    update!(status: "dispatched", dispatched_at: dispatched_at || now, recipients_count: deliveries.count)
    log_activity
    deliveries.where(status: "queued").ids.each { |delivery_id| DeliveryJob.perform_later(delivery_id) }
    self
  end

  def scheduled?
    status == "scheduled"
  end

  def subject_line
    subject.presence || default_subject
  end

  def default_subject
    case kind
    when "invitation" then "You're invited: #{event.title}"
    when "cancellation" then "Cancelled: #{event.title}"
    when "reminder" then "Reminder: #{event.title}"
    else "Update: #{event.title}"
    end
  end

  def delivery_counts
    deliveries.group(:status).count
  end

  private
    def reachable_guests
      channels.map do |channel|
        channel == "sms" ? Guest.where.not(phone: nil).where(unsubscribed_at: nil) : Guest.emailable
      end.reduce { |a, b| a.or(b) } || Guest.none
    end

    def channels_supported
      errors.add(:channels, "must include at least one of email or SMS") if channels.empty?
      if channels.include?("sms") && !Messaging.sms_enabled?
        errors.add(:channels, "SMS isn't configured yet (see README: SMS integration)")
      end
    end

    def schedule_in_future
      errors.add(:scheduled_for, "must be in the future") if scheduled_for.nil? || scheduled_for <= Time.current
    end

    def log_activity
      return if kind == "invitation" && recipients_count.zero?

      Activity.record(event: event, user: author, action: "message_sent",
        data: { kind: kind, message_id: id, recipients: recipients_count })
    end
end
