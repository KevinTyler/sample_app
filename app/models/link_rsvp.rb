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

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: EmailFormat::REGEXP }

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
      email_personal_link(existing, "Here's your personal link to view the invitation and update your RSVP.")
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
    email_personal_link(@guest, "Thanks for your RSVP! Use this link any time to view the invitation or change your response.")
    true
  end

  private
    def copy_errors(record)
      record.errors.each { |error| errors.add(error.attribute == :base ? :base : error.attribute, error.message) }
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
