# Stripe events for Checkout sessions, verified with the Stripe-Signature header
# (HMAC-SHA256 with STRIPE_WEBHOOK_SECRET, 5-minute timestamp tolerance).
class Webhooks::StripeController < Webhooks::BaseController
  def create
    return head(:not_found) unless Payments.provider == "stripe" && Payments::StripeGateway.configured?

    event = Payments::StripeGateway.verify_webhook!(request.raw_post, request.headers["Stripe-Signature"])
    session = event.dig("data", "object") || {}
    payment = find_payment(session)
    return head(:ok) unless payment # not ours; acknowledge so Stripe stops retrying

    case event["type"]
    when "checkout.session.completed", "checkout.session.async_payment_succeeded"
      if session["payment_status"] == "paid" && session["amount_total"].to_i == payment.amount_cents
        payment.mark_paid!(provider_payment_id: session["payment_intent"])
      end
    when "checkout.session.expired"
      payment.mark_expired!
    when "checkout.session.async_payment_failed"
      payment.update!(status: "failed") if payment.status == "pending"
    end
    head :ok
  rescue Payments::StripeGateway::SignatureError, JSON::ParserError
    head :bad_request
  end

  private
    def find_payment(session)
      Payment.find_by(provider: "stripe", provider_session_id: session["id"].to_s) ||
        Payment.find_by(provider: "stripe", id: session.dig("metadata", "payment_id").to_i)
    end
end
