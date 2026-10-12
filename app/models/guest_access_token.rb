# Personal RSVP links look like /i/<token>, where the token is
#
#   <key (16 chars, random, stored on the guest)><signature (24 chars, HMAC of key)>
#
# Only the random key is stored. The signature is derived from the application's
# secret_key_base, so a leaked database alone is not enough to forge working links,
# and the host can always re-display a guest's link without us storing it in plain text.
# Rotating a guest's key immediately invalidates their old link.
module GuestAccessToken
  KEY_LENGTH = 16
  SIGNATURE_LENGTH = 24
  FORMAT = /\A[A-Za-z0-9_-]{#{KEY_LENGTH + SIGNATURE_LENGTH}}\z/

  module_function

  def generate_key
    SecureRandom.base58(KEY_LENGTH)
  end

  def for(key)
    key + signature(key)
  end

  # Returns the key if the token is well formed and correctly signed, otherwise nil.
  def verified_key(token)
    return nil unless token.is_a?(String) && token.match?(FORMAT)

    key = token[0, KEY_LENGTH]
    given = token[KEY_LENGTH, SIGNATURE_LENGTH]
    ActiveSupport::SecurityUtils.secure_compare(given, signature(key)) ? key : nil
  end

  # The code inside a guest's check-in QR pass: "<guest id>-<12 chars>". It is derived from the
  # guest's key, so it's revoked with the link, but it is *not* the RSVP token — door staff who
  # scan it can check the guest in without gaining the ability to change their RSVP.
  def check_in_code(guest)
    sig = Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, "check-in:#{guest.id}:#{guest.token_key}").byteslice(0, 9), padding: false)
    "#{guest.id}-#{sig}"
  end

  def signature(key)
    digest = OpenSSL::HMAC.digest("SHA256", secret, key)
    Base64.urlsafe_encode64(digest.byteslice(0, 18), padding: false)
  end

  def secret
    @secret ||= Rails.application.key_generator.generate_key("larkspur/guest-access-token", 32)
  end
end
