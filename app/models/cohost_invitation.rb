# An emailed invitation to co-host an event. The raw token exists only in the email link; we store
# its SHA-256 digest. It must be accepted by a signed-in account with the invited email address,
# can be used once, and expires.
class CohostInvitation < ApplicationRecord
  VALID_FOR = 14.days

  belongs_to :event
  belongs_to :invited_by, class_name: "User", optional: true

  attr_reader :token

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, length: { maximum: 254 }, format: { with: EmailFormat::REGEXP }
  validates :role, inclusion: { in: EventMembership::ROLES.keys }
  validate :not_already_on_event, on: :create

  before_validation :generate_token, on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token)
    return nil unless token.is_a?(String) && token.length.between?(20, 64)

    find_by(token_digest: digest(token))
  end

  def usable?
    accepted_at.nil? && expires_at.future?
  end

  def acceptable_by?(user)
    usable? && user.email_address == email
  end

  def accept!(user)
    raise ArgumentError, "invitation can't be accepted by this account" unless acceptable_by?(user)

    transaction do
      membership = event.memberships.find_or_initialize_by(user: user)
      membership.update!(role: role, invited_by: invited_by) unless event.owner_id == user.id
      update!(accepted_at: Time.current)
      Activity.record(event: event, user: user, action: "cohost_joined", data: { role: role })
    end
  end

  def role_name
    EventMembership::ROLES.dig(role, :name)
  end

  private
    def generate_token
      @token = SecureRandom.urlsafe_base64(24)
      self.token_digest = self.class.digest(@token)
      self.expires_at ||= VALID_FOR.from_now
    end

    def not_already_on_event
      return unless event && email.present?

      if event.owner.email_address == email || event.members.exists?(email_address: email)
        errors.add(:email, "already has access to this event")
      end
    end
end
