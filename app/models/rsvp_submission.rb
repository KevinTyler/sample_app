# Validates and records one guest's RSVP, including answers to custom questions.
#
# Guests submit through their personal link (limits enforced). Hosts may also record a
# response on a guest's behalf (e.g. a phoned-in RSVP); `by_host: true` skips the deadline
# and capacity checks so the host can make exceptions deliberately.
class RsvpSubmission
  include ActiveModel::Model
  include ActiveModel::Attributes

  STATUSES = %w[yes no maybe].freeze

  attribute :status, :string
  attribute :party_size, :integer
  attribute :guest_note, :string
  attr_accessor :guest, :answers, :by_host, :user

  validates :status, inclusion: { in: STATUSES, message: "Please choose a response" }
  validates :guest_note, length: { maximum: 1000 }
  validate :maybe_allowed
  validate :party_size_within_limits
  validate :rsvps_open, unless: :by_host
  validate :answers_valid

  def self.from_guest(guest)
    new(guest: guest, status: guest.rsvp_pending? ? nil : guest.rsvp_status,
      party_size: guest.responded? ? guest.party_size : 1, guest_note: guest.guest_note,
      answers: guest.rsvp_answers.to_h { |a| [ a.event_question_id.to_s, a.value ] })
  end

  def event
    guest.event
  end

  def answers
    @answers.respond_to?(:to_unsafe_h) ? @answers.to_unsafe_h : (@answers || {}).to_h
  end

  def answer_for(question)
    answers[question.id.to_s]
  end

  def effective_party_size
    status == "no" ? 0 : party_size.to_i
  end

  def save
    return false unless valid?

    previous_status = guest.rsvp_status
    Guest.transaction do
      # SQLite serializes write transactions; on other databases this row lock makes the
      # capacity check below safe against two guests grabbing the last spots at once.
      event.lock! unless ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)

      if !by_host && status == "yes" && (remaining = event.spots_remaining(excluding: guest)) && effective_party_size > remaining
        errors.add(:party_size, remaining.zero? ? "Sorry — this event is full." : "Only #{remaining} #{'spot'.pluralize(remaining)} left. Please reduce your party size.")
        raise ActiveRecord::Rollback
      end

      guest.update!(rsvp_status: status, party_size: effective_party_size, guest_note: guest_note.to_s.strip.presence,
        responded_at: Time.current)
      save_answers!
      Activity.record(event: event, guest: guest, user: (user if by_host),
        action: previous_status == "pending" ? "rsvp_submitted" : "rsvp_changed",
        data: { from: previous_status, to: status, party_size: effective_party_size, by_host: by_host.present? })
    end
    errors.empty?
  end

  def questions_for_status
    event.questions.select { |q| q.applies_to_status?(status) }
  end

  private
    def maybe_allowed
      errors.add(:status, "Maybe isn't an option for this event") if status == "maybe" && !event.allow_maybe
    end

    def party_size_within_limits
      return if status == "no" || status.blank?

      if party_size.to_i < 1
        errors.add(:party_size, "must be at least 1")
      elsif party_size.to_i > guest.max_party_size
        errors.add(:party_size, guest.max_party_size == 1 ? "must be 1 (this invitation is for one)" : "can be at most #{guest.max_party_size}")
      end
    end

    def rsvps_open
      if event.cancelled?
        errors.add(:base, "This event has been cancelled.")
      elsif !event.published?
        errors.add(:base, "This event isn't accepting responses yet.")
      elsif !event.accepting_rsvps?
        errors.add(:base, "The RSVP deadline has passed. Please contact the host to change your response.")
      end
    end

    def answers_valid
      return if status.blank?

      questions_for_status.each do |question|
        value = answer_for(question).to_s.strip
        if value.blank?
          errors.add(:base, "Please answer: #{question.prompt}") if question.required? && !by_host
        elsif value.length > question.max_answer_length
          errors.add(:base, "Your answer to “#{question.prompt}” is too long")
        elsif question.choice? && !question.options.include?(value)
          errors.add(:base, "Please pick one of the listed answers for: #{question.prompt}")
        end
      end
    end

    def save_answers!
      applicable = questions_for_status.map(&:id)
      guest.rsvp_answers.where.not(event_question_id: applicable).delete_all

      questions_for_status.each do |question|
        value = answer_for(question).to_s.strip
        answer = guest.rsvp_answers.find_or_initialize_by(event_question: question)
        if value.blank?
          answer.destroy! if answer.persisted?
        else
          answer.update!(value: value)
        end
      end
    end
end
