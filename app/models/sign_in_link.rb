# A short-lived, single-use link that signs a host in (sent by the texting assistant so they can
# jump from a text thread into the design studio). Only a digest of the token is stored.
class SignInLink < ApplicationRecord
  TTL = 30.minutes

  belongs_to :user

  validates :redirect_path, format: { with: %r{\A/(?![/\\])[^\s]*\z}, message: "must be a local path" }

  def self.issue!(user, redirect_path)
    token = SecureRandom.urlsafe_base64(24)
    create!(user: user, token_digest: digest(token), redirect_path: redirect_path, expires_at: TTL.from_now)
    token
  end

  def self.find_usable(token)
    return unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{32}\z/)

    where(token_digest: digest(token), used_at: nil).where("expires_at > ?", Time.current).first
  end

  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "sign-in-link:#{token}")
  end

  # Atomically consumes the link; only one request can win.
  def consume!
    self.class.where(id: id, used_at: nil).update_all(used_at: Time.current) == 1
  end
end
