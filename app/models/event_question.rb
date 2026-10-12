# A custom question shown on the RSVP form ("Meal preference?", "Song request").
class EventQuestion < ApplicationRecord
  KINDS = {
    "short_text" => "Short answer",
    "long_text" => "Paragraph",
    "choice" => "Multiple choice (pick one)"
  }.freeze
  APPLIES_TO = {
    "attending" => "Only guests who are coming (or might)",
    "all" => "Everyone who responds"
  }.freeze
  COPYABLE_ATTRIBUTES = %w[prompt kind options required applies_to position].freeze
  MAX_OPTIONS = 12
  MAX_ANSWER_LENGTH = { "short_text" => 200, "long_text" => 1000, "choice" => 200 }.freeze

  belongs_to :event, inverse_of: :questions
  has_many :rsvp_answers, dependent: :destroy

  normalizes :prompt, with: ->(v) { v.squish }

  validates :prompt, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :applies_to, inclusion: { in: APPLIES_TO.keys }
  validate :choices_are_valid

  before_validation :clean_options
  before_create :assign_position

  def choice?
    kind == "choice"
  end

  # Text-area friendly editing of choices: one option per line.
  def options_text
    Array(options).join("\n")
  end

  def options_text=(text)
    self.options = text.to_s.lines
  end

  def applies_to_status?(status)
    applies_to == "all" || %w[yes maybe].include?(status.to_s)
  end

  def max_answer_length
    MAX_ANSWER_LENGTH.fetch(kind, 200)
  end

  private
    def clean_options
      self.options = choice? ? Array(options).map { |o| o.to_s.squish }.reject(&:blank?).uniq.first(MAX_OPTIONS) : []
    end

    def choices_are_valid
      return unless choice?

      errors.add(:options_text, "needs at least two choices") if options.size < 2
      errors.add(:options_text, "choices must be 100 characters or fewer") if options.any? { |o| o.length > 100 }
    end

    def assign_position
      self.position = (event.questions.maximum(:position) || 0) + 1 if position.to_i.zero?
    end
end
