# A host's thread with the Cordially agent: by text (SMS or WhatsApp) or on the web ("Today").
# For texts the phone number is the identity: possession of it is what links the thread to an
# account (new accounts are created from the thread; an existing account is linked only after its
# owner confirms by email, or by texting a one-time code shown to them on the web). The web thread
# belongs to the signed-in user.
class AssistantConversation < ApplicationRecord
  TEXT_CHANNELS = %w[sms whatsapp].freeze
  CHANNELS = (TEXT_CHANNELS + %w[web]).freeze
  HISTORY_LIMIT = 24
  DAILY_INBOUND_LIMIT = Integer(ENV.fetch("ASSISTANT_DAILY_LIMIT", "120"))

  belongs_to :user, optional: true
  belongs_to :event, optional: true
  has_many :messages, -> { order(:created_at, :id) }, class_name: "AssistantMessage", dependent: :delete_all

  validates :channel, inclusion: { in: CHANNELS }
  validates :address, presence: true
  validates :address, format: { with: PhoneNumber::FORMAT }, if: :texting?
  validates :user, presence: true, if: :web?

  def self.for_web(user)
    find_or_create_by!(channel: "web", address: "web:#{user.id}") { |c| c.user = user }
  rescue ActiveRecord::RecordNotUnique
    find_by!(channel: "web", address: "web:#{user.id}")
  end

  def self.for(channel:, address:)
    find_or_create_by!(channel: channel, address: address)
  rescue ActiveRecord::RecordNotUnique
    find_by!(channel: channel, address: address)
  end

  def web? = channel == "web"
  def texting? = channel.in?(TEXT_CHANNELS)

  def opted_out?
    opted_out_at.present?
  end

  # WhatsApp only allows free-form messages within 24 hours of the person's last message.
  def can_message?
    !opted_out? && (channel.in?(%w[sms web]) || (last_inbound_at && last_inbound_at > 23.hours.ago))
  end

  def over_daily_limit?
    messages.where(direction: "in", created_at: 1.day.ago..).count > DAILY_INBOUND_LIMIT
  end

  def recent_messages(limit = HISTORY_LIMIT)
    messages.reorder(created_at: :desc, id: :desc).limit(limit).to_a.reverse
  end

  def latest_inbound
    messages.where(direction: "in").reorder(created_at: :desc, id: :desc).first
  end

  # Sends a reply on this thread's channel and records it. Cards (an event, an import preview, a
  # proposal to approve) are shown on the web; texts carry the words alone.
  def reply!(body, media_urls: [], cards: [])
    body = body.to_s.strip
    return if (body.empty? && cards.empty?) || opted_out?
    return messages.create!(direction: "out", body: body, cards: cards) if web?

    gateway = Messaging.gateway_for(channel)
    receipt = gateway.send_text(to: address, body: body.truncate(1500), media_urls: media_urls, metadata: { assistant_conversation_id: id })
    messages.create!(direction: "out", body: body, cards: cards, provider_message_id: receipt&.message_id)
  end

  # The agent has been asked something and hasn't answered yet.
  def awaiting_reply?
    last = messages.reorder(created_at: :desc, id: :desc).first
    last&.inbound? && last.created_at > 3.minutes.ago
  end

  def data_value(key)
    (data || {})[key.to_s]
  end

  def store!(**values)
    update!(data: (data || {}).merge(values.stringify_keys))
  end
end
