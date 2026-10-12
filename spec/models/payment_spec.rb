require "rails_helper"

RSpec.describe Payment do
  let(:event) { create(:event, :published, ticket_price: "25", currency: "usd") }
  let(:guest) { create(:guest, event: event, plus_ones_allowed: 3, rsvp_status: "yes", party_size: 2) }
  let(:urls) { { success_url: "http://example.com/ok", cancel_url: "http://example.com/back" } }

  it "parses and formats money" do
    expect(Money.parse_cents("$1,250.50")).to eq(125_050)
    expect(Money.parse_cents("abc")).to be_nil
    expect(Money.format(2500, "usd")).to eq("$25 USD")
    expect(Money.format(1999, "eur")).to eq("€19.99 EUR")
  end

  it "validates the ticket price" do
    expect(build(:event, ticket_price: "0.10")).not_to be_valid
    expect(build(:event, ticket_price: "twenty")).not_to be_valid
    expect(build(:event, ticket_price: "")).to be_valid.and(have_attributes(ticketed?: false))
  end

  it "charges attending guests for their whole party, and nothing for maybe or no" do
    expect(guest.amount_due_cents).to eq(5000)
    guest.update!(rsvp_status: "maybe")
    expect(guest.amount_due_cents).to eq(0)
  end

  it "reuses the same pending payment and checkout session when Pay is clicked twice" do
    first = described_class.checkout_for!(guest, **urls)
    second = described_class.checkout_for!(guest.reload, **urls)
    expect(second).to eq(first)
    expect(second.checkout_url).to eq(first.checkout_url)
    expect(event.payments.count).to eq(1)
  end

  it "marks a payment paid exactly once and records it" do
    payment = described_class.checkout_for!(guest, **urls)
    expect(payment.mark_paid!(provider_payment_id: "pi_1")).to be(true)
    expect(payment.mark_paid!(provider_payment_id: "pi_2")).to be(false)
    expect(payment.reload.provider_payment_id).to eq("pi_1")
    expect(guest.reload.amount_due_cents).to eq(0)
    expect(event.collected_cents).to eq(5000)
  end

  it "asks only for the difference when a paid guest adds people" do
    described_class.checkout_for!(guest, **urls).mark_paid!
    guest.update!(party_size: 3)
    top_up = described_class.checkout_for!(guest.reload, **urls)
    expect(top_up.amount_cents).to eq(2500)
    expect(top_up.quantity).to eq(3)
  end

  it "only redirects to the provider's own checkout host" do
    payment = event.payments.new(provider: "stripe", checkout_url: "https://checkout.stripe.com/c/pay/cs_1")
    expect(payment.safe_checkout_url(app_host: "example.com")).to eq("https://checkout.stripe.com/c/pay/cs_1")
    payment.checkout_url = "https://evil.example/c/pay"
    expect(payment.safe_checkout_url(app_host: "example.com")).to be_nil
    payment.checkout_url = "http://checkout.stripe.com/c/pay/cs_1"
    expect(payment.safe_checkout_url(app_host: "example.com")).to be_nil
  end

  it "starts a fresh checkout after the previous one expired" do
    payment = described_class.checkout_for!(guest, **urls)
    payment.mark_expired!
    again = described_class.checkout_for!(guest.reload, **urls)
    expect(again).to eq(payment)
    expect(again.status).to eq("pending")
    expect(again.checkout_url).to be_present
  end
end
