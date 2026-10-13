class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :owned_events, class_name: "Event", foreign_key: :owner_id, inverse_of: :owner, dependent: :destroy
  has_many :event_memberships, dependent: :destroy
  has_many :contacts, dependent: :delete_all
  has_many :contact_imports, dependent: :delete_all
  has_many :agent_proposals, dependent: :delete_all
  has_many :assistant_conversations, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :email_address, presence: true, length: { maximum: 254 },
    format: { with: EmailFormat::REGEXP }, uniqueness: true
  validates :password, length: { minimum: 10, maximum: 72 }, allow_nil: true

  RSVP_NOTIFICATION_OPTIONS = {
    "instant" => "Email me each reply as it arrives",
    "daily" => "One summary email a day",
    "off" => "Don't email me about replies"
  }.freeze
  validates :rsvp_notifications, inclusion: { in: RSVP_NOTIFICATION_OPTIONS.keys }

  AGENT_REACH_OPTIONS = {
    "text" => "Text me (on my connected phone)",
    "email" => "Email me",
    "off" => "Only here in Cordially"
  }.freeze
  validates :agent_reach, inclusion: { in: AGENT_REACH_OPTIONS.keys }
  validates :default_host_name, length: { maximum: 120 }
  validates :default_plus_ones, numericality: { only_integer: true, in: 0..Guest::MAX_PLUS_ONES }
  validate { errors.add(:time_zone, "is not a recognized time zone") if time_zone.present? && !ActiveSupport::TimeZone[time_zone] }
  validates :phone_country_code, format: { with: /\A[1-9]\d{0,3}\z/ }, allow_blank: true

  validate do
    errors.add(:agent_reach, "needs a connected phone first") if agent_reach == "text" && will_save_change_to_agent_reach? && !texting_conversation
  end

  # The phone thread the agent can text this host on (most recently used), if any.
  def texting_conversation
    assistant_conversations.where(channel: AssistantConversation::TEXT_CHANNELS, opted_out_at: nil).order(last_inbound_at: :desc).first
  end

  PHONE_LINK_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze
  PHONE_LINK_TTL = 15.minutes

  # A short code the host texts to the agent's number ("LINK 4F7KQ2") to connect that phone.
  # Only its digest is stored; it works once, for 15 minutes.
  def issue_phone_link_code!
    code = Array.new(6) { PHONE_LINK_ALPHABET[SecureRandom.random_number(PHONE_LINK_ALPHABET.size)] }.join
    update!(phone_link_code_digest: self.class.phone_link_digest(code), phone_link_expires_at: PHONE_LINK_TTL.from_now)
    code
  end

  def self.phone_link_digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "phone-link:#{code.to_s.upcase}")
  end

  # The user whose unexpired code this is (and spends it), or nil.
  def self.claim_phone_link(code)
    user = where(phone_link_code_digest: phone_link_digest(code)).where(phone_link_expires_at: Time.current..).first
    return unless user

    claimed = where(id: user.id, phone_link_code_digest: user.phone_link_code_digest).update_all(phone_link_code_digest: nil, phone_link_expires_at: nil)
    user.reload if claimed == 1
  end

  # Calling codes guessed from a time zone, for hosts who haven't said where their numbers are.
  ZONE_CALLING_CODES = {
    "Europe/London" => "44", "Europe/Dublin" => "353", "Asia/Kolkata" => "91", "America/Sao_Paulo" => "55", "America/Mexico_City" => "52",
    "Europe/Paris" => "33", "Europe/Berlin" => "49", "Europe/Madrid" => "34", "Europe/Rome" => "39", "Europe/Lisbon" => "351",
    "Pacific/Auckland" => "64", "Africa/Johannesburg" => "27", "Asia/Tokyo" => "81", "Asia/Seoul" => "82"
  }.freeze

  def effective_phone_country_code
    return phone_country_code if phone_country_code.present?

    zone = time_zone.presence || "America/New_York"
    ZONE_CALLING_CODES[zone] || ("61" if zone.start_with?("Australia/")) || ("1" if zone.start_with?("America/"))
  end

  # Settings every new event starts with (the host's "usual settings").
  def event_defaults
    {
      host_name: default_host_name.presence || name, time_zone: time_zone.presence || "America/New_York",
      allow_maybe: default_allow_maybe, track_kids: default_track_kids, default_plus_ones: default_plus_ones,
      auto_nudge: default_auto_nudge, auto_day_before: default_auto_day_before
    }
  end

  # Every event this user may open in the host dashboard: owned or co-hosted.
  def accessible_events
    Event.where(owner_id: id).or(Event.where(id: event_memberships.select(:event_id)))
  end

  def first_name
    name.split.first
  end
end
