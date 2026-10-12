require "rails_helper"

RSpec.describe "Ticketed events", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host, ticket_price: "20", currency: "usd") }
  let(:guest) { create(:guest, event: event, plus_ones_allowed: 1) }
  let(:token) { guest.access_token }

  it "takes a guest from RSVP through the (test) checkout to paid" do
    patch guest_rsvp_path(token), params: { rsvp: { status: "yes", party_size: "2" } }
    follow_redirect!
    expect(page_text).to include("complete your payment", "Pay $40 USD")

    post guest_pay_path(token)
    checkout = response.location
    expect(checkout).to include("/dev/checkout/")

    get checkout
    expect(page_text).to include("$40 USD", "2 tickets")

    post checkout
    expect(response.location).to include("/i/#{token}")
    expect(guest.reload.amount_due_cents).to eq(0)

    get guest_invitation_path(token)
    expect(page_text).to include("Paid", "$40 USD for 2 tickets")

    sign_in host
    get event_path(event)
    expect(page_text).to match(%r{\$40 USD</strong> collected})
  end

  it "rejects a tampered test checkout link" do
    get "/dev/checkout/not-a-real-token"
    expect(response).to have_http_status(:not_found)
  end

  it "doesn't ask maybes or declines to pay" do
    patch guest_rsvp_path(token), params: { rsvp: { status: "maybe", party_size: "1" } }
    post guest_pay_path(token)
    expect(flash[:notice]).to include("Nothing to pay")
  end

  it "lets the owner set and remove a price" do
    sign_in host
    patch event_path(event), params: { event: { ticket_price: "35.50", currency: "eur" } }
    expect(event.reload).to have_attributes(ticket_price_cents: 3550, currency: "eur")
    patch event_path(event), params: { event: { ticket_price: "" } }
    expect(event.reload).not_to be_ticketed
  end

  it "lets only the owner set the price" do
    cohost = create(:user)
    event.memberships.create!(user: cohost, role: "editor")
    sign_in cohost
    patch event_path(event), params: { event: { ticket_price: "1", title: "Edited" } }
    expect(event.reload).to have_attributes(title: "Edited", ticket_price_cents: 2000)
  end

  describe "with Stripe" do
    around do |example|
      env = { "PAYMENTS_PROVIDER" => "stripe", "STRIPE_SECRET_KEY" => "sk_test_123", "STRIPE_WEBHOOK_SECRET" => "whsec_test" }
      env.each { |k, v| ENV[k] = v }
      example.run
    ensure
      env.each_key { |k| ENV.delete(k) }
    end

    before { guest.update!(rsvp_status: "yes", party_size: 2) }

    def stripe_event(type, session)
      payload = { type: type, data: { object: session } }.to_json
      timestamp = Time.current.to_i
      signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec_test", "#{timestamp}.#{payload}")
      [ payload, "t=#{timestamp},v1=#{signature}" ]
    end

    it "creates a Checkout session and records payment from a signed webhook" do
      stub = stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
        .with(headers: { "Idempotency-Key" => /\Alarkspur-payment-\d+-\d+\z/ }) { |request|
          form = Rack::Utils.parse_nested_query(request.body)
          form["mode"] == "payment" && form.dig("line_items", "0", "quantity") == "2" &&
            form.dig("line_items", "0", "price_data", "unit_amount") == "2000"
        }
        .to_return(status: 200, body: { id: "cs_test_1", url: "https://checkout.stripe.com/c/pay/cs_test_1" }.to_json)

      post guest_pay_path(token)
      expect(stub).to have_been_requested.once
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_1")
      payment = event.payments.sole

      payload, header = stripe_event("checkout.session.completed",
        { id: "cs_test_1", payment_status: "paid", amount_total: 4000, payment_intent: "pi_9", metadata: { payment_id: payment.id.to_s } })
      post webhooks_stripe_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => header }
      expect(response).to have_http_status(:ok)
      expect(payment.reload).to have_attributes(status: "paid", provider_payment_id: "pi_9")
    end

    it "rejects forged webhooks and mismatched amounts" do
      payment = event.payments.create!(guest: guest, amount_cents: 4000, currency: "usd", quantity: 2, provider: "stripe",
        idempotency_key: "k1", provider_session_id: "cs_test_2")

      payload, _ = stripe_event("checkout.session.completed", { id: "cs_test_2", payment_status: "paid", amount_total: 4000 })
      post webhooks_stripe_path, params: payload, headers: { "Stripe-Signature" => "t=#{Time.current.to_i},v1=deadbeef" }
      expect(response).to have_http_status(:bad_request)

      payload, header = stripe_event("checkout.session.completed", { id: "cs_test_2", payment_status: "paid", amount_total: 1 })
      post webhooks_stripe_path, params: payload, headers: { "Stripe-Signature" => header }
      expect(payment.reload.status).to eq("pending")

      payload, header = stripe_event("checkout.session.expired", { id: "cs_test_2" })
      post webhooks_stripe_path, params: payload, headers: { "Stripe-Signature" => header }
      expect(payment.reload.status).to eq("expired")
    end
  end
end
