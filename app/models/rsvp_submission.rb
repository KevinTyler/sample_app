# Validates and records one guest's RSVP, including answers to custom questions.
#
# Guests submit through their personal link (limits enforced). Hosts may also record a
# response on a guest's behalf (e.g. a phoned-in RSVP); `by_host: true` skips the deadline
# and capacity checks so the host can make exceptions deliberately.
#
# Error messages are whole sentences in the guest's language (guest.errors.*); show them with
# `form_errors(rsvp, full: false)` so Rails doesn't prefix the English attribute name.
class RsvpSubmission
  include ActiveModel::Model
  include ActiveModel::Attributes

  STATUSES = %w[yes no maybe].freeze

  attribute :status, :string
  attribute :party_size, :integer
  attribute :adults, :integer
  attribute :kids, :integer
  attribute :guest_note, :string
  attr_accessor :guest, :answers, :by_host, :user
  attr_writer :plus_one_names, :schedule

  validates :status, inclusion: { in: STATUSES, message: ->(*) { I18n.t("guest.errors.choose_response") } }
  validates :guest_note, length: { maximum: 1000, message: ->(*) { I18n.t("guest.errors.note_too_long") } }
  validate :maybe_allowed
  validate :party_size_within_limits
  validate :rsvps_open, unless: :by_host
  validate :answers_valid
  validate :plus_one_names_valid
  validate :picks_a_schedule_item

  def self.from_guest(guest)
    new(guest: guest, status: guest.rsvp_pending? ? nil : guest.rsvp_status,
      party_size: guest.responded? ? guest.party_size : 1, guest_note: guest.guest_note,
      adults: guest.responded? ? [ guest.adults_count, 1 ].max : 1, kids: guest.responded? ? guest.kids_count : 0,
      plus_one_names: guest.plus_one_names,
      schedule: guest.schedule_replies.to_h { |r| [ r.schedule_item_id.to_s, r.attending ? "1" : "0" ] },
      answers: guest.rsvp_answers.to_h { |a| [ a.event_question_id.to_s, a.value ] })
  end

  # { "<schedule item id>" => "1" | "0" } for multi-part events; unanswered parts count as attending.
  def schedule
    raw = @schedule
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    (raw || {}).to_h.transform_keys(&:to_s).transform_values(&:to_s)
  end

  def attending_item?(item)
    return false if status == "no"

    schedule.key?(item.id.to_s) ? schedule[item.id.to_s] == "1" : true
  end

  def replyable_items
    @replyable_items ||= guest.event.schedule_for(guest).select(&:collects_replies)
  end

  def plus_one_names
    raw = @plus_one_names
    raw = raw.values if raw.respond_to?(:values) # fields_for-style hash {"0" => "Sam"}
    Array(raw).map { |n| n.to_s.squish }
  end

  # With adult/kid counts on, the party size is their sum.
  def party_size
    event_tracks_kids? && (adults || kids) ? adults.to_i + kids.to_i : super
  end

  def kids_count
    status == "no" || !event_tracks_kids? ? 0 : kids.to_i
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
        errors.add(:party_size, remaining.zero? ? t("full") : t("spots_left", count: remaining))
        raise ActiveRecord::Rollback
      end

      guest.update!(rsvp_status: status, party_size: effective_party_size, kids_count: kids_count,
        plus_one_names: (status == "no" || !event.ask_plus_one_names? ? [] : plus_one_names.first([ effective_party_size - 1, 0 ].max)),
        guest_note: guest_note.to_s.strip.presence, responded_at: Time.current)
      save_answers!
      save_schedule_replies!
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
    def t(key, **options)
      I18n.t("guest.errors.#{key}", **options)
    end

    def event_tracks_kids?
      guest&.event&.track_kids?
    end

    def maybe_allowed
      errors.add(:status, t("no_maybe")) if status == "maybe" && !event.allow_maybe
    end

    def party_size_within_limits
      return if status == "no" || status.blank?

      if event_tracks_kids? && adults.to_i < 1
        errors.add(:adults, t("need_adult"))
      elsif (event_tracks_kids? && kids.to_i.negative?) || party_size.to_i < 1
        errors.add(:party_size, t("party_min"))
      elsif party_size.to_i > guest.max_party_size
        errors.add(:party_size, t("party_max", count: guest.max_party_size))
      end
    end

    def rsvps_open
      if event.cancelled?
        errors.add(:base, t("cancelled"))
      elsif !event.collects_replies?
        errors.add(:base, t("no_replies"))
      elsif !event.published?
        errors.add(:base, t("not_open"))
      elsif !event.accepting_rsvps?
        errors.add(:base, t("deadline_passed"))
      end
    end

    def picks_a_schedule_item
      return unless status.in?(%w[yes maybe]) && replyable_items.any?

      errors.add(:base, t("pick_a_part")) if replyable_items.none? { |item| attending_item?(item) }
    end

    def save_schedule_replies!
      replyable_items.each do |item|
        reply = guest.schedule_replies.find_or_initialize_by(schedule_item: item)
        reply.update!(attending: attending_item?(item))
      end
    end

    def plus_one_names_valid
      errors.add(:base, t("names_too_long")) if plus_one_names.any? { |n| n.length > 80 }
    end

    def answers_valid
      return if status.blank?

      questions_for_status.each do |question|
        value = answer_for(question).to_s.strip
        if value.blank?
          errors.add(:base, t("answer_required", question: question.prompt)) if question.required? && !by_host
        elsif value.length > question.max_answer_length
          errors.add(:base, t("answer_too_long", question: question.prompt))
        elsif question.choice? && !question.options.include?(value)
          errors.add(:base, t("answer_choice", question: question.prompt))
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
