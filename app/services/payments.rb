# Payment gateway adapters share one interface:
#   create_checkout(payment, success_url:, cancel_url:) -> Payments::Checkout
# PAYMENTS_PROVIDER=stripe uses Stripe Checkout (needs STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET);
# development and test default to a local fake checkout page. Without a provider in production,
# ticketed events can't be enabled.
module Payments
  Checkout = Data.define(:url, :session_id)

  class NotConfigured < StandardError; end

  module_function

  def provider
    ENV.fetch("PAYMENTS_PROVIDER") { Rails.env.production? ? nil : "fake" }.presence
  end

  def gateway
    case provider
    when "stripe" then StripeGateway
    when "fake" then FakeGateway
    else raise NotConfigured, "Payments are not configured"
    end
  end

  def enabled?
    provider.present? && gateway.configured?
  rescue NotConfigured
    false
  end
end
