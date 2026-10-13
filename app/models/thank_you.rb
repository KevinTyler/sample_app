# A thank-you note to one person: a photo or short video (kids recording their thanks gift by
# gift) and/or a written message. It opens at /t/<token>, a private link like a guest's
# invitation link; the host sends it by text or email, or shares it from their own phone.
class ThankYou < ApplicationRecord
  MEDIA_TYPES = %w[image/jpeg image/png image/webp image/gif image/heic image/heif
                   video/mp4 video/quicktime video/webm video/3gpp].freeze
  MEDIA_MAX_SIZE = 100.megabytes
  KEY_LENGTH = 16
  TOKEN_FORMAT = /\A[A-Za-z0-9_-]{40}\z/

  belongs_to :event
  belongs_to :guest, optional: true
  belongs_to :gift, optional: true
  has_one_attached :media

  normalizes :recipient_name, with: ->(v) { v.to_s.squish }
  normalizes :recipient_email, with: ->(v) { v.to_s.strip.downcase.presence }
  normalizes :recipient_phone, with: ->(v) { PhoneNumber.normalize(v) }
  normalizes :message, with: ->(v) { v.to_s.strip.presence }
  normalizes :signed, with: ->(v) { v.to_s.squish.presence }

  validates :recipient_name, presence: true, length: { maximum: 100 }
  validates :recipient_email, length: { maximum: 254 }, format: { with: EmailFormat::REGEXP }, allow_nil: true
  validates :recipient_phone, format: { with: PhoneNumber::FORMAT }, allow_nil: true
  validates :message, length: { maximum: 2000 }
  validates :token_key, presence: true, uniqueness: true
  validate :media_is_acceptable

  before_validation :assign_token_key, on: :create
  before_validation :copy_recipient, on: :create

  scope :sent, -> { where.not(sent_at: nil) }

  def self.find_by_token(token)
    return unless token.is_a?(String) && token.match?(TOKEN_FORMAT)

    key = token.first(KEY_LENGTH)
    record = find_by(token_key: key)
    record if record && ActiveSupport::SecurityUtils.secure_compare(record.token, token)
  end

  def token
    token_key + Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "thank-you:#{token_key}"), padding: false).first(24)
  end

  # Something worth sending: a photo/video or a note.
  def ready?
    media.attached? || message.present?
  end

  # Attached and already uploaded (a rejected upload is attached but not stored).
  def stored_media?
    media.attached? && media.blob&.persisted?
  end

  def video?
    media.attached? && media.blob.content_type.start_with?("video/")
  end

  def image?
    media.attached? && media.blob.content_type.start_with?("image/")
  end

  def sent?
    sent_at.present?
  end

  def first_name
    recipient_name.split.first
  end

  def headline
    gift ? "Thank you for the #{gift.description.downcase_first}!" : "Thank you, #{first_name}!"
  end

  # The text that goes with the link, in the host's voice.
  def share_text(url)
    who = signed.to_s.sub(/\A(love|thanks|xo+),?\s*/i, "").presence || event.display_host_name
    "#{first_name}, #{who} made you a thank-you#{" for the #{gift.description.downcase_first}" if gift}: #{url}"
  end

  private
    def assign_token_key
      self.token_key ||= SecureRandom.base58(KEY_LENGTH)
    end

    def copy_recipient
      return unless guest

      self.recipient_name = guest.name if recipient_name.blank?
      self.recipient_email ||= guest.email
      self.recipient_phone ||= guest.phone
    end

    def media_is_acceptable
      return unless media.attached?

      errors.add(:media, "must be a photo or video (JPEG, PNG, HEIC, MP4, MOV or WebM)") unless media.blob.content_type.in?(MEDIA_TYPES)
      errors.add(:media, "must be smaller than 100 MB") if media.blob.byte_size > MEDIA_MAX_SIZE
    end
end
