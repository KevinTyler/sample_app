class Event < ApplicationRecord
  LOCAL_TIME_FIELDS = %i[starts_at ends_at rsvp_deadline].freeze
  LOCAL_TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?\z/
  DEFAULT_DURATION = 3.hours

  belongs_to :owner, class_name: "User", inverse_of: :owned_events
  belongs_to :inspired_by_event, class_name: "Event", optional: true
  has_many :guests, dependent: :destroy
  has_many :questions, -> { order(:position, :id) }, class_name: "EventQuestion",
    dependent: :destroy, inverse_of: :event
  has_many :messages, dependent: :destroy
  has_many :activities, dependent: :delete_all
  has_many :guest_imports, dependent: :delete_all
  has_many :memberships, class_name: "EventMembership", dependent: :delete_all
  has_many :members, through: :memberships, source: :user
  has_many :cohost_invitations, dependent: :delete_all

  # Optional uploaded artwork or photo for the invitation. SVG is deliberately not accepted
  # (it can carry script); only raster formats are served.
  has_one_attached :artwork
  ARTWORK_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  ARTWORK_MAX_SIZE = 8.megabytes

  has_many :payments, dependent: :destroy
  has_many :guestbook_entries, dependent: :delete_all
  has_many :links, class_name: "EventLink", dependent: :delete_all
  has_many :schedule_items, dependent: :destroy
  has_many :gifts, dependent: :destroy
  has_many :thank_yous, dependent: :destroy
  has_many_attached :photos

  CARD_TYPES = {
    "invitation" => { name: "Invitation", summary: "Guests reply yes, no or maybe" },
    "save_the_date" => { name: "Save the date", summary: "Mark calendars now; send the invitation later" },
    "announcement" => { name: "Announcement", summary: "Share news — no replies needed" }
  }.freeze
  MAX_PHOTOS = 12
  LOCALES = { "en" => "English", "es" => "Español", "pt-BR" => "Português (Brasil)", "fr" => "Français", "hi" => "हिन्दी" }.freeze
  CURRENCIES = {
    "usd" => { symbol: "$", name: "US dollar" }, "cad" => { symbol: "$", name: "Canadian dollar" },
    "eur" => { symbol: "€", name: "Euro" }, "gbp" => { symbol: "£", name: "British pound" },
    "aud" => { symbol: "$", name: "Australian dollar" }
  }.freeze

  enum :status, { draft: "draft", published: "published", cancelled: "cancelled" }, default: "draft", validate: true

  has_secure_token :share_token

  normalizes :title, :host_name, :location_name, :address, with: ->(v) { v.squish.presence }
  normalizes :video_url, with: ->(v) { v.strip.presence }

  validates :title, presence: true, length: { maximum: 120 }
  validates :host_name, :location_name, length: { maximum: 120 }
  validates :address, length: { maximum: 300 }
  validates :description, length: { maximum: 5000 }
  validates :cancellation_note, length: { maximum: 2000 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000 }, allow_nil: true
  validates :default_plus_ones, numericality: { only_integer: true, in: 0..20 }
  validates :nudge_days_before, numericality: { only_integer: true, in: 1..14 }
  validates :video_url, length: { maximum: 500 },
    format: { with: %r{\Ahttps?://[^\s<>"']+\z}i, message: "must be a full link starting with http:// or https://" },
    allow_nil: true
  validates :starts_at, presence: { message: "is required before publishing" }, unless: -> { draft? || announcement? }
  validates :card_type, inclusion: { in: CARD_TYPES.keys }
  validates :locale, inclusion: { in: LOCALES.keys }
  validate :photos_are_acceptable
  validate :time_zone_must_exist
  validate :local_times_must_parse
  validate :ends_after_start
  validate :deadline_before_end
  validate :starts_in_future, on: :publish
  validate :artwork_is_acceptable
  validates :currency, inclusion: { in: CURRENCIES.keys }
  validates :ticket_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 50, less_than_or_equal_to: 1_000_000,
    message: "must be between 0.50 and 10,000" }, allow_nil: true
  validate :payments_available, if: :ticketed?
  validate :ticket_price_parses

  before_validation :resolve_local_times
  after_commit :sync_auto_reminders, on: %i[create update], if: :reminder_inputs_changed?

  REMINDER_INPUTS = %w[status rsvp_deadline starts_at time_zone auto_nudge nudge_days_before auto_day_before].freeze

  scope :upcoming, -> { where("starts_at IS NULL OR starts_at >= ?", 1.day.ago).order(Arel.sql("starts_at IS NULL, starts_at")) }
  scope :past, -> { where(starts_at: ...1.day.ago).order(starts_at: :desc) }

  # --- Times -----------------------------------------------------------------

  # Form fields are entered as wall-clock time in the event's own time zone
  # (e.g. "2026-11-05T19:00" in America/Chicago) and stored in UTC.
  LOCAL_TIME_FIELDS.each do |field|
    define_method(:"#{field}_local") do
      if instance_variable_defined?(:"@#{field}_local")
        instance_variable_get(:"@#{field}_local")
      else
        public_send(field)&.in_time_zone(zone)&.strftime("%Y-%m-%dT%H:%M")
      end
    end

    define_method(:"#{field}_local=") do |value|
      instance_variable_set(:"@#{field}_local", value.to_s.strip.presence)
    end
  end

  def zone
    ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone["UTC"]
  end

  def local(time)
    time&.in_time_zone(zone)
  end

  def effective_ends_at
    ends_at || (starts_at && starts_at + DEFAULT_DURATION)
  end

  def online?
    video_url.present?
  end

  def in_person?
    location_name.present? || address.present?
  end

  # --- Lifecycle -------------------------------------------------------------

  def publish
    return false unless draft?

    self.status = "published"
    self.published_at = Time.current
    return true if save(context: :publish)

    self.status = "draft"
    self.published_at = nil
    false
  end

  def cancel(note: nil)
    return false if cancelled?

    update(status: "cancelled", cancelled_at: Time.current, cancellation_note: note.to_s.strip.presence,
      calendar_sequence: calendar_sequence + 1)
  end

  # A new draft with the same details, design and questions. Guests are copied only on request,
  # and always come over fresh: new private links, no RSVP or delivery history.
  def duplicate(include_guests: false)
    copy = dup
    copy.assign_attributes(
      title: "Copy of #{title}".truncate(120), status: "draft", share_token: self.class.generate_unique_secure_token,
      published_at: nil, cancelled_at: nil, cancellation_note: nil, calendar_sequence: 0
    )

    transaction do
      copy.save!
      questions.each { |q| copy.questions.create!(q.attributes.slice(*EventQuestion::COPYABLE_ATTRIBUTES)) }
      copy.artwork.attach(artwork.blob) if artwork.attached?
      if include_guests
        guests.find_each do |guest|
          copy.guests.create!(guest.attributes.slice(*Guest::COPYABLE_ATTRIBUTES))
        end
      end
    end
    copy
  end

  # Bumped whenever guests' calendar entries should refresh (time/place changes, cancellation).
  def touch_calendar!
    increment!(:calendar_sequence)
  end

  CALENDAR_FIELDS = %w[starts_at ends_at time_zone location_name address video_url title].freeze

  def calendar_details_changed?
    (saved_changes.keys & CALENDAR_FIELDS).any?
  end

  # --- RSVPs -----------------------------------------------------------------

  def invitation?
    card_type == "invitation"
  end

  def save_the_date?
    card_type == "save_the_date"
  end

  def announcement?
    card_type == "announcement"
  end

  # Only invitations collect replies; save-the-dates and announcements are one-way.
  def collects_replies?
    invitation?
  end

  # The parts of a multi-part event this guest is invited to.
  def schedule_for(guest)
    schedule_items.select { |item| item.invited?(guest) }
  end

  def card_type_name
    CARD_TYPES.dig(card_type, :name) || "Invitation"
  end

  def rsvp_closes_at
    rsvp_deadline || starts_at
  end

  def accepting_rsvps?(now = Time.current)
    collects_replies? && published? && (rsvp_closes_at.nil? || now <= rsvp_closes_at)
  end

  def attending_count(excluding: nil)
    scope = guests.where(rsvp_status: "yes")
    scope = scope.where.not(id: excluding.id) if excluding
    scope.sum(:party_size)
  end

  def spots_remaining(excluding: nil)
    return nil unless capacity

    [ capacity - attending_count(excluding: excluding), 0 ].max
  end

  def rsvp_summary
    counts = guests.group(:rsvp_status).count
    {
      invited: guests.count,
      yes: counts.fetch("yes", 0),
      no: counts.fetch("no", 0),
      maybe: counts.fetch("maybe", 0),
      pending: counts.fetch("pending", 0),
      attending: attending_count,
      maybe_headcount: guests.where(rsvp_status: "maybe").sum(:party_size),
      attending_kids: guests.where(rsvp_status: "yes").sum(:kids_count),
      viewed: guests.where.not(first_viewed_at: nil).count,
      sent: guests.where.not(invited_at: nil).count
    }
  end

  # --- Tickets ---------------------------------------------------------------

  def ticketed?
    ticket_price_cents.present?
  end

  def ticket_price
    ticket_price_cents && format("%.2f", ticket_price_cents / 100.0)
  end

  def ticket_price=(value)
    self.ticket_price_cents = value.to_s.strip.presence && Money.parse_cents(value)
    @invalid_ticket_price = value.to_s.strip.present? && ticket_price_cents.nil?
  end

  def collected_cents
    payments.paid.sum(:amount_cents)
  end

  def design_settings
    InvitationDesign.for(self)
  end

  def regenerate_share_token!
    update!(share_token: self.class.generate_unique_secure_token)
  end

  def group_names
    guests.where.not(group_name: nil).distinct.order(:group_name).pluck(:group_name)
  end

  # "owner", "editor", "checkin" or nil.
  def role_for(user)
    return nil unless user
    return "owner" if owner_id == user.id

    @roles_by_user ||= {}
    @roles_by_user.fetch(user.id) { @roles_by_user[user.id] = memberships.find_by(user_id: user.id)&.role }
  end

  def display_host_name
    host_name.presence || owner.name
  end

  private
    def reminder_inputs_changed?
      (saved_changes.keys & REMINDER_INPUTS).any?
    end

    def sync_auto_reminders
      AutoReminders.sync(self)
    end

    def resolve_local_times
      @unparseable_times = []
      LOCAL_TIME_FIELDS.each do |field|
        next unless instance_variable_defined?(:"@#{field}_local")

        raw = instance_variable_get(:"@#{field}_local")
        if raw.nil?
          public_send(:"#{field}=", nil)
        elsif raw.match?(LOCAL_TIME_FORMAT) && (parsed = zone.parse(raw))
          public_send(:"#{field}=", parsed)
        else
          @unparseable_times << field
        end
      end
    end

    def time_zone_must_exist
      errors.add(:time_zone, "is not a recognized time zone") unless ActiveSupport::TimeZone[time_zone.to_s]
    end

    def local_times_must_parse
      Array(@unparseable_times).each { |field| errors.add(field, "is not a valid date and time") }
    end

    def ends_after_start
      return unless starts_at && ends_at

      errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
    end

    def deadline_before_end
      return unless rsvp_deadline && starts_at

      errors.add(:rsvp_deadline, "must be before the event ends") if rsvp_deadline > effective_ends_at
    end

    def artwork_is_acceptable
      return unless artwork.attached?

      unless artwork.blob.content_type.in?(ARTWORK_TYPES)
        errors.add(:artwork, "must be a PNG, JPEG, WebP or GIF image")
      end
      errors.add(:artwork, "must be smaller than 8 MB") if artwork.blob.byte_size > ARTWORK_MAX_SIZE
    end

    def photos_are_acceptable
      return unless photos.attached?

      errors.add(:photos, "can be at most #{MAX_PHOTOS}") if photos.size > MAX_PHOTOS
      photos.each do |photo|
        next unless photo.blob

        errors.add(:photos, "must be PNG, JPEG, WebP or GIF images") unless photo.blob.content_type.in?(ARTWORK_TYPES)
        errors.add(:photos, "must each be smaller than 8 MB") if photo.blob.byte_size > ARTWORK_MAX_SIZE
      end
    end

    def payments_available
      errors.add(:ticket_price, "can't be set until payments are configured (see README)") unless Payments.enabled?
    end

    def ticket_price_parses
      errors.add(:ticket_price, "isn't a valid amount") if @invalid_ticket_price
    end

    def starts_in_future
      errors.add(:starts_at, "must be in the future to publish") if starts_at && starts_at <= Time.current
    end
end
