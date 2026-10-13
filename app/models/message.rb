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
  KINDS = %w[invitation save_the_date announcement update reminder cancellation rsvp_confirmation].freeze
  # The card itself, in its three forms (Event#card_type). Each guest gets each at most once.
  CARD_KINDS = %w[invitation save_the_date announcement].freeze
  CHANNELS = %w[email sms].freeze
  STATUSES = %w[draft scheduled dispatching dispatched].freeze

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
  validate :schedule_in_future, if: -> { status == "scheduled" }, on: :create
  validate :schedule_parses

  before_validation :resolve_scheduled_for

  scope :due, -> { where(status: "scheduled").where(scheduled_for: ..Time.current) }
  scope :for_guests, -> { where(kind: %w[update reminder cancellation]) }

  # Finds the message for this idempotency key, or creates it. Safe under concurrency: a racing
  # insert loses on the unique index and we return the winner's row.
  def self.idempotent_create!(idempotency_key:, **attributes)
    find_by(idempotency_key: idempotency_key) || create!(attributes.merge(idempotency_key: idempotency_key))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    raise if error.is_a?(ActiveRecord::RecordInvalid) && !error.record.errors.of_kind?(:idempotency_key, :taken)

    find_by!(idempotency_key: idempotency_key)
  end

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
    unless kind.in?(CARD_KINDS + %w[rsvp_confirmation])
      scope = scope.where.not(invited_at: nil).or(scope.where.not(rsvp_status: "pending"))
    end
    if kind.in?(CARD_KINDS) && !audience.resend?
      already = Delivery.joins(:message)
        .where(messages: { event_id: event_id, kind: kind })
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

  # The compose form takes the send time as wall-clock time in the event's time zone.
  def scheduled_for_local
    @scheduled_for_local || scheduled_for&.in_time_zone(event.zone)&.strftime("%Y-%m-%dT%H:%M")
  end

  def scheduled_for_local=(value)
    @scheduled_for_local = value.to_s.strip.presence
  end

  # Called by the scheduler (and safe to call from several workers at once): only the caller that
  # moves the message out of "scheduled" gets to dispatch it.
  def dispatch_scheduled!
    now = Time.current
    claimed = self.class.where(id: id, status: "scheduled").where(scheduled_for: ..now)
      .update_all(status: "dispatching", updated_at: now)
    return false unless claimed == 1

    reload.dispatch!
    true
  end

  def enqueue_scheduled_dispatch
    DispatchScheduledMessageJob.set(wait_until: scheduled_for).perform_later(id)
  end

  def subject_line
    subject.presence || default_subject
  end

  def default_subject
    case kind
    when "invitation" then "You're invited: #{event.title}"
    when "save_the_date" then "Save the date: #{event.title}"
    when "announcement" then "#{event.title} — news from #{event.display_host_name}"
    when "cancellation" then "Cancelled: #{event.title}"
    when "reminder" then "Reminder: #{event.title}"
    when "rsvp_confirmation" then "Your RSVP link: #{event.title}"
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

    def resolve_scheduled_for
      return unless instance_variable_defined?(:@scheduled_for_local)

      raw = @scheduled_for_local
      self.scheduled_for = raw && event && raw.match?(Event::LOCAL_TIME_FORMAT) ? event.zone.parse(raw) : nil
    end

    def schedule_parses
      errors.add(:scheduled_for, "is not a valid date and time") if @scheduled_for_local && scheduled_for.nil?
    end

    def log_activity
      return if kind == "rsvp_confirmation" || (kind.in?(CARD_KINDS) && recipients_count.zero?)

      Activity.record(event: event, user: author, action: "message_sent",
        data: { kind: kind, message_id: id, recipients: recipients_count })
    end
end
