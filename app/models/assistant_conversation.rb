# A host's texting thread with the Cordially assistant (SMS or WhatsApp). The phone number is the
# identity: possession of it is what links the thread to an account (new accounts are created
# from the thread; an existing account is linked only after its owner confirms by email).
class AssistantConversation < ApplicationRecord
  CHANNELS = %w[sms whatsapp].freeze
  HISTORY_LIMIT = 24
  DAILY_INBOUND_LIMIT = Integer(ENV.fetch("ASSISTANT_DAILY_LIMIT", "120"))

  belongs_to :user, optional: true
  belongs_to :event, optional: true
  has_many :messages, -> { order(:created_at, :id) }, class_name: "AssistantMessage", dependent: :delete_all

  validates :channel, inclusion: { in: CHANNELS }
  validates :address, presence: true, format: { with: PhoneNumber::FORMAT }

  def self.for(channel:, address:)
    find_or_create_by!(channel: channel, address: address)
  rescue ActiveRecord::RecordNotUnique
    find_by!(channel: channel, address: address)
  end

  def opted_out?
    opted_out_at.present?
  end

  # WhatsApp only allows free-form messages within 24 hours of the person's last message.
  def can_message?
    !opted_out? && (channel == "sms" || (last_inbound_at && last_inbound_at > 23.hours.ago))
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

  # Sends a reply on this thread's channel and records it.
  def reply!(body, media_urls: [])
    body = body.to_s.strip
    return if body.empty? || opted_out?

    gateway = Messaging.gateway_for(channel)
    receipt = gateway.send_text(to: address, body: body.truncate(1500), media_urls: media_urls, metadata: { assistant_conversation_id: id })
    messages.create!(direction: "out", body: body, provider_message_id: receipt&.message_id)
  end

  def data_value(key)
    (data || {})[key.to_s]
  end

  def store!(**values)
    update!(data: (data || {}).merge(values.stringify_keys))
  end
end
