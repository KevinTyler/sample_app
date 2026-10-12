require "rails_helper"

RSpec.describe "SMS adapters" do
  let(:event) { create(:event, :published, title: "Picnic") }
  let(:guest) { create(:guest, event: event, phone: "+15550102000") }
  let(:message) { event.messages.create!(kind: "invitation", channels: %w[sms], idempotency_key: "s1", audience: {}) }
  let(:delivery) { message.deliveries.create!(guest: guest, channel: "sms", recipient: guest.phone) }

  describe Messaging::Sms::TwilioAdapter do
    around do |example|
      env = { "TWILIO_ACCOUNT_SID" => "AC123", "TWILIO_AUTH_TOKEN" => "secret", "TWILIO_FROM_NUMBER" => "+15005550006" }
      env.each { |k, v| ENV[k] = v }
      example.run
    ensure
      env.each_key { |k| ENV.delete(k) }
    end

    let(:endpoint) { "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json" }

    it "posts the message and returns Twilio's SID" do
      stub = stub_request(:post, endpoint).with(basic_auth: %w[AC123 secret], body: hash_including("To" => "+15550102000", "From" => "+15005550006"))
        .to_return(status: 201, body: { sid: "SM42" }.to_json)
      receipt = described_class.deliver(delivery)
      expect(stub).to have_been_requested
      expect(receipt).to have_attributes(provider: "twilio", message_id: "SM42")
    end

    it "treats 4xx responses as permanent and 5xx as retryable" do
      stub_request(:post, endpoint).to_return(status: 400, body: { message: "Invalid 'To'" }.to_json)
      expect { described_class.deliver(delivery) }.to raise_error(Delivery::PermanentError, /Invalid 'To'/)

      stub_request(:post, endpoint).to_return(status: 503)
      expect { described_class.deliver(delivery) }.to raise_error(RuntimeError, /503/)
    end

    it "requires E.164 numbers" do
      delivery.update!(recipient: "5550102000")
      expect { described_class.deliver(delivery) }.to raise_error(Delivery::PermanentError, /country code/)
    end
  end

  it "is unavailable in production without a provider" do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect(Messaging.sms_enabled?).to be(false)
    expect(event.messages.new(kind: "invitation", channels: %w[sms], idempotency_key: "s2")).not_to be_valid
  end
end
