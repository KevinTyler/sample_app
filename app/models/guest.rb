class Guest < ApplicationRecord
  RSVP_STATUSES = %w[pending yes no maybe].freeze
  SOURCES = %w[manual csv link].freeze
  MAX_PLUS_ONES = 20
  COPYABLE_ATTRIBUTES = %w[name email phone group_name plus_ones_allowed host_notes].freeze

  belongs_to :event
  has_many :rsvp_answers, dependent: :destroy
  has_many :deliveries, dependent: :destroy
  has_many :activities, dependent: :nullify
  has_many :payments, dependent: :nullify
  has_many :gifts, dependent: :nullify
  has_many :thank_yous, dependent: :nullify

  enum :rsvp_status, RSVP_STATUSES.index_by(&:itself), default: "pending", prefix: :rsvp, validate: true

  normalizes :name, with: ->(v) { v.squish }
  normalizes :email, with: ->(v) { v.strip.downcase.presence }
  normalizes :phone, with: ->(v) { PhoneNumber.normalize(v) }
  normalizes :group_name, with: ->(v) { v.squish.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, length: { maximum: 254 }, format: { with: EmailFormat::REGEXP }, allow_nil: true
  validates :email, uniqueness: { scope: :event_id, message: "is already on this guest list" }, allow_nil: true
  validates :phone, format: { with: PhoneNumber::FORMAT, message: "should contain 7–15 digits, optionally starting with +" }, allow_nil: true
  validates :group_name, length: { maximum: 60 }
  validates :plus_ones_allowed, numericality: { only_integer: true, in: 0..MAX_PLUS_ONES }
  validates :party_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :guest_note, length: { maximum: 1000 }
  validates :kids_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :kids_within_party
  validate :plus_one_names_valid
  validates :host_notes, length: { maximum: 2000 }
  validates :source, inclusion: { in: SOURCES }
  validates :token_key, presence: true, uniqueness: true

  before_validation :assign_token_key, on: :create

  scope :attending, -> { where(rsvp_status: "yes") }
  scope :responded, -> { where.not(rsvp_status: "pending") }
  scope :uninvited, -> { where(invited_at: nil) }
  scope :emailable, -> { where.not(email: nil).where(unsubscribed_at: nil) }
  scope :search, ->(query) {
    term = "%#{sanitize_sql_like(query.to_s.strip.downcase)}%"
    where("LOWER(guests.name) LIKE :t OR guests.email LIKE :t OR guests.phone LIKE :t OR LOWER(guests.group_name) LIKE :t", t: term)
  }

  def self.find_by_access_token(token)
    key = GuestAccessToken.verified_key(token)
    key && find_by(token_key: key)
  end

  def access_token
    GuestAccessToken.for(token_key)
  end

  def check_in_code
    GuestAccessToken.check_in_code(self)
  end

  def self.find_by_check_in_code(code)
    id = code.to_s[/\A(\d+)-[A-Za-z0-9_-]{12}\z/, 1]
    guest = id && find_by(id: id)
    guest if guest && ActiveSupport::SecurityUtils.secure_compare(guest.check_in_code, code.to_s)
  end

  # --- Tickets ---------------------------------------------------------------

  def amount_paid_cents
    payments.select { |p| p.status == "paid" }.sum(&:amount_cents)
  end

  # What a guest who said yes still owes for their party. Maybes and declines owe nothing.
  def amount_due_cents
    return 0 unless event.ticketed? && rsvp_yes?

    [ event.ticket_price_cents * party_size - amount_paid_cents, 0 ].max
  end

  def payment_state
    return nil unless event.ticketed? && rsvp_yes?

    amount_due_cents.zero? ? "paid" : (amount_paid_cents.positive? ? "partial" : "unpaid")
  end

  def checked_in?
    checked_in_at.present?
  end

  def check_in!(count:, by: nil)
    count = count.to_i.clamp(1, [ party_size, max_party_size, 1 ].max)
    update!(checked_in_at: checked_in_at || Time.current, checked_in_count: count)
    Activity.record(event: event, guest: self, user: by, action: "checked_in", data: { count: count })
  end

  def undo_check_in!(by: nil)
    update!(checked_in_at: nil, checked_in_count: 0)
    Activity.record(event: event, guest: self, user: by, action: "check_in_undone")
  end

  # Invalidates the guest's current personal link.
  def rotate_access_token!
    update!(token_key: GuestAccessToken.generate_key)
  end

  def max_party_size
    1 + plus_ones_allowed
  end

  def adults_count
    [ party_size - kids_count, 0 ].max
  end

  def plus_one_names
    Array(super).map(&:to_s)
  end

  def plus_one_names=(names)
    super(Array(names).map { |n| n.to_s.squish }.compact_blank.first(MAX_PLUS_ONES))
  end

  # "2 adults, 1 kid" when the event tracks children; otherwise just the headcount.
  def party_breakdown
    return party_size.to_s unless event.track_kids? && (rsvp_yes? || rsvp_maybe?)

    [ ("#{adults_count} #{'adult'.pluralize(adults_count)}" if adults_count.positive?),
      ("#{kids_count} #{'kid'.pluralize(kids_count)}" if kids_count.positive?) ].compact.join(", ")
  end

  def responded?
    !rsvp_pending?
  end

  def unsubscribed?
    unsubscribed_at.present?
  end

  def emailable?
    email.present? && !unsubscribed?
  end

  def address_for(channel)
    case channel.to_s
    when "email" then email if emailable?
    when "sms" then phone if phone.present? && !unsubscribed?
    end
  end

  def first_name
    name.split.first
  end

  def record_view!
    now = Time.current
    first_view = first_viewed_at.nil?
    update_columns(first_viewed_at: first_viewed_at || now, last_viewed_at: now)
    Activity.record(event: event, guest: self, action: "viewed") if first_view
  end

  # Latest invitation delivery, for the host's "delivery status" column.
  def invitation_delivery
    deliveries.joins(:message).where(messages: { kind: Message::CARD_KINDS }).order(:created_at).last
  end

  private
    def kids_within_party
      errors.add(:kids_count, "can't be more than the party size") if kids_count.to_i > party_size.to_i
    end

    def plus_one_names_valid
      errors.add(:plus_one_names, "are too long (80 characters each)") if plus_one_names.any? { |n| n.length > 80 }
    end

    def assign_token_key
      self.token_key ||= GuestAccessToken.generate_key
    end
end
