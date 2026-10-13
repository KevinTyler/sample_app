# Be sure to restart your server when you modify this file.

# Strict Content Security Policy. Scripts and stylesheets must come from our own origin or carry
# the per-request nonce; inline style="" attributes are not allowed, so dynamic invitation styling
# is emitted as a nonced <style> block built only from validated values (see InvitationDesign).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob
    policy.media_src   :self, :blob # thank-you videos (served through the app) and local previews
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src :self
    policy.frame_src   :self
    policy.frame_ancestors :none
    policy.base_uri    :self
    # Paying redirects (after a form POST) to the provider's hosted checkout page.
    policy.form_action :self, *([ "https://checkout.stripe.com" ] if ENV["PAYMENTS_PROVIDER"] == "stripe")
  end

  # The nonce must stay the same across Turbo Drive visits (Turbo swaps in new <body> content under
  # the original page's CSP), so it is derived from the session id, as Rails recommends for Turbo.
  # For first-time visitors this creates the session (and its id) in the same response, so their
  # first page and later Turbo visits share a nonce that no other visitor can predict.
  config.content_security_policy_nonce_generator = ->(request) {
    request.session[:csp] = 1 unless request.session.key?(:csp)
    session_id = request.session.id.to_s
    session_id.present? ? Digest::SHA256.base64digest("csp-nonce:#{session_id}").first(24) : SecureRandom.base64(18)
  }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
