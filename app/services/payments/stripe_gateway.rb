require "net/http"

module Payments
  # Stripe Checkout over its REST API (no SDK dependency).
  #   PAYMENTS_PROVIDER=stripe STRIPE_SECRET_KEY=sk_… STRIPE_WEBHOOK_SECRET=whsec_…
  # Point a Stripe webhook at /webhooks/stripe for checkout.session.completed / .expired.
  module StripeGateway
    API = "https://api.stripe.com/v1".freeze
    SIGNATURE_TOLERANCE = 5.minutes

    class SignatureError < StandardError; end

    module_function

    def configured?
      secret_key.present? && webhook_secret.present?
    end

    def create_checkout(payment, success_url:, cancel_url:)
      event = payment.event
      params = {
        "mode" => "payment",
        "success_url" => success_url,
        "cancel_url" => cancel_url,
        "client_reference_id" => payment.id.to_s,
        "metadata[payment_id]" => payment.id.to_s,
        "line_items[0][quantity]" => payment.quantity.to_s,
        "line_items[0][price_data][currency]" => payment.currency,
        "line_items[0][price_data][unit_amount]" => (payment.amount_cents / payment.quantity).to_s,
        "line_items[0][price_data][product_data][name]" => "#{event.title} — ticket".truncate(120)
      }
      params["customer_email"] = payment.guest.email if payment.guest&.email
      # Amounts that don't divide evenly by quantity are charged as a single line.
      if payment.amount_cents % payment.quantity != 0
        params["line_items[0][quantity]"] = "1"
        params["line_items[0][price_data][unit_amount]"] = payment.amount_cents.to_s
      end

      # One key per checkout attempt: protects this request against network-level replays, while a new
      # attempt (e.g. after a session expired) still gets a fresh session. Double clicks never reach
      # here twice — Payment#ensure_checkout! reuses the stored session under a row lock.
      body = post("/checkout/sessions", params, idempotency_key: "cordially-payment-#{payment.id}-#{Time.current.to_i}")
      Checkout.new(url: body.fetch("url"), session_id: body.fetch("id"))
    end

    # Verifies the Stripe-Signature header and returns the parsed event.
    def verify_webhook!(payload, header, now: Time.current)
      parts = header.to_s.split(",").map { |kv| kv.split("=", 2) }.group_by(&:first).transform_values { |v| v.map(&:last) }
      timestamp = parts["t"]&.first.to_i
      raise SignatureError, "stale timestamp" if timestamp.zero? || (now.to_i - timestamp).abs > SIGNATURE_TOLERANCE

      expected = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret.to_s, "#{timestamp}.#{payload}")
      valid = Array(parts["v1"]).any? { |sig| ActiveSupport::SecurityUtils.secure_compare(sig, expected) }
      raise SignatureError, "signature mismatch" unless valid

      JSON.parse(payload)
    end

    def post(path, params, idempotency_key:)
      uri = URI("#{API}#{path}")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(secret_key, "")
      request["Idempotency-Key"] = idempotency_key
      request.set_form_data(params)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      body = JSON.parse(response.body) rescue {}
      raise "Stripe error #{response.code}: #{body.dig('error', 'message')}" unless response.code.to_i.between?(200, 299)

      body
    end

    def secret_key = ENV["STRIPE_SECRET_KEY"]
    def webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
  end
end
