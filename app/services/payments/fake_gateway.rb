module Payments
  # Local stand-in for a hosted checkout page (/dev/checkout/...). The link is signed so it can't be
  # used to mark someone else's payment as paid.
  module FakeGateway
    module_function

    def configured?
      true
    end

    def create_checkout(payment, success_url:, cancel_url:)
      token = verifier.generate({ "payment_id" => payment.id, "success" => success_url, "cancel" => cancel_url }, expires_in: 1.day)
      # Same host as the page the guest came from (taken from the signed success URL).
      origin = URI.parse(success_url)
      url = Rails.application.routes.url_helpers.dev_checkout_url(token, host: origin.host, port: origin.port, protocol: origin.scheme)
      Checkout.new(url: url, session_id: "fake_#{payment.id}_#{SecureRandom.hex(6)}")
    end

    def verifier
      @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("larkspur/fake-checkout", 32),
        digest: "SHA256", serializer: JSON, url_safe: true
      )
    end
  end
end
