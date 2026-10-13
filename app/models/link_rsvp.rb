# An RSVP submitted through the event's public share link (when the host allows open RSVPs).
#
# New email address → the person is added to the guest list (source "link"), their RSVP is
# recorded, and they're emailed their personal link for later changes.
# Email already on the list → we never touch that guest's RSVP or reveal it; we just email the
# address its personal link (throttled), so knowing someone's email isn't enough to answer for them.
class LinkRsvp
  include ActiveModel::Model
  include ActiveModel::Attributes

  LINK_EMAIL_THROTTLE = 10.minutes

  attribute :name, :string
  attribute :email, :string
  attribute :status, :string
  attribute :party_size, :integer
  attribute :adults, :integer
  attribute :kids, :integer
  attribute :guest_note, :string
  attr_accessor :event, :answers, :plus_one_names, :schedule
  attr_reader :guest, :outcome

  validate :name_and_email_present

  def plus_one_names
    Array(@plus_one_names)
  end

  def answer_for(question)
    (answers || {}).to_h.stringify_keys[question.id.to_s]
  end

  def save
    return false unless valid?

    if (existing = event.guests.find_by(email: email.strip.downcase))
      @guest = existing
      @outcome = :existing
      email_personal_link(existing, I18n.t("guest.mail.link_existing"))
      return true
    end

    @guest = event.guests.new(name: name, email: email, source: "link", plus_ones_allowed: event.default_plus_ones)
    rsvp = RsvpSubmission.new(guest: @guest, status: status, party_size: party_size, adults: adults, kids: kids,
      plus_one_names: plus_one_names, schedule: schedule, guest_note: guest_note, answers: answers)
    return copy_errors(@guest) unless @guest.valid?
    return copy_errors(rsvp) unless rsvp.valid?

    Guest.transaction do
      @guest.save!
      rsvp.save || raise(ActiveRecord::Rollback)
    end
    return copy_errors(rsvp) if rsvp.errors.any?

    @outcome = :created
    email_personal_link(@guest, I18n.t("guest.mail.link_created"))
    true
  end

  private
    def name_and_email_present
      errors.add(:base, I18n.t("guest.errors.name_required")) if name.blank? || name.length > 100
      errors.add(:base, I18n.t("guest.errors.email_invalid")) unless email.to_s.length <= 254 && email.to_s.match?(EmailFormat::REGEXP)
    end

    # RSVP messages are whole sentences already; the guest's own are standard Rails ones, so keep their field name.
    def copy_errors(record)
      record.errors.each { |error| errors.add(error.attribute, record.is_a?(Guest) ? error.full_message : error.message) }
      false
    end

    # One email per guest per throttle window, however many times the form is submitted.
    def email_personal_link(guest, body)
      window = Time.current.to_i / LINK_EMAIL_THROTTLE.to_i
      message = event.messages.idempotent_create!(idempotency_key: "link-#{guest.id}-#{window}", kind: "rsvp_confirmation",
        channels: %w[email], body: body, audience: { "guest_ids" => [ guest.id ], "resend" => true })
      message.dispatch! unless message.status == "dispatched"
    end
end
