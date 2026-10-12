# Be sure to restart your server when you modify this file.

# Strict Content Security Policy. Scripts and stylesheets must come from our own origin or carry
# the per-request nonce; inline style="" attributes are not allowed, so dynamic invitation styling
# is emitted as a nonced <style> block built only from validated values (see InvitationDesign).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src :self
    policy.frame_src   :self
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # The nonce must stay the same across Turbo Drive visits (Turbo swaps in new <body> content under
  # the original page's CSP), so it is derived from the session id, as Rails recommends for Turbo.
  config.content_security_policy_nonce_generator = ->(request) {
    Digest::SHA256.base64digest("csp-nonce:#{request.session.id}").first(24)
  }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
