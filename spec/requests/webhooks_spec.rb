require "rails_helper"

RSpec.describe "Provider webhooks", type: :request do
  let(:event) { create(:event, :published) }
  let!(:guest) { create(:guest, event: event, phone: "+15550102000") }
  let(:message) { event.messages.create!(kind: "invitation", channels: %w[email], idempotency_key: "w1", audience: {}) }

  describe "email" do
    let!(:delivery) do
      message.deliveries.create!(guest: guest, channel: "email", recipient: guest.email, status: "sent",
        provider_message_id: "delivery-1-123@cordially.localhost")
    end

    around do |example|
      ENV["EMAIL_WEBHOOK_TOKEN"] = "a-long-shared-webhook-token"
      example.run
    ensure
      ENV.delete("EMAIL_WEBHOOK_TOKEN")
    end

    def post_event(body, token: "a-long-shared-webhook-token")
      post webhooks_email_path, params: body.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    end

    it "marks bounces" do
      post_event({ message_id: "<delivery-1-123@cordially.localhost>", event: "bounced", reason: "Mailbox does not exist" })
      expect(response).to have_http_status(:ok)
      expect(delivery.reload).to have_attributes(status: "bounced", error_message: "Mailbox does not exist")
    end

    it "accepts SendGrid's event format and unsubscribes on spam complaints" do
      post_event([ { "smtp-id" => "<delivery-1-123@cordially.localhost>", "event" => "delivered" },
                   { "smtp-id" => "<delivery-1-123@cordially.localhost>", "event" => "spamreport" } ])
      expect(delivery.reload.status).to eq("delivered")
      expect(guest.reload).to be_unsubscribed
    end

    it "rejects bad tokens and is off when no token is configured" do
      post_event({ message_id: "x", event: "bounced" }, token: "wrong-token-wrong-token")
      expect(response).to have_http_status(:unauthorized)

      ENV.delete("EMAIL_WEBHOOK_TOKEN")
      post_event({ message_id: "x", event: "bounced" })
      expect(response).to have_http_status(:not_found)
      expect(delivery.reload.status).to eq("sent")
    end
  end

  describe "Twilio" do
    around do |example|
      ENV["TWILIO_AUTH_TOKEN"] = "twilio-token"
      example.run
    ensure
      ENV.delete("TWILIO_AUTH_TOKEN")
    end

    def signed_post(path, params, token: "twilio-token")
      url = "http://www.example.com#{path}"
      signature = Webhooks::TwilioController.signature(token, url, params.stringify_keys)
      post path, params: params, headers: { "X-Twilio-Signature" => signature }
    end

    it "records delivery status for signed callbacks" do
      delivery = message.deliveries.create!(guest: guest, channel: "sms", recipient: guest.phone, status: "sent", provider_message_id: "SM42")
      signed_post(webhooks_twilio_status_path, { MessageSid: "SM42", MessageStatus: "undelivered", ErrorCode: "30003" })
      expect(response).to have_http_status(:no_content)
      expect(delivery.reload).to have_attributes(status: "bounced", error_message: "Twilio error 30003")
    end

    it "rejects unsigned or forged requests" do
      post webhooks_twilio_inbound_path, params: { From: guest.phone, Body: "STOP" }, headers: { "X-Twilio-Signature" => "forged" }
      expect(response).to have_http_status(:forbidden)
      expect(guest.reload).not_to be_unsubscribed
    end

    it "honors STOP replies" do
      signed_post(webhooks_twilio_inbound_path, { From: "+15550102000", Body: " stop " })
      expect(response.body).to eq("<Response/>")
      expect(guest.reload).to be_unsubscribed
    end
  end
end
