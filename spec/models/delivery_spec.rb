require "rails_helper"

RSpec.describe Delivery do
  let(:event) { create(:event, :published) }
  let(:guest) { create(:guest, event: event) }
  let(:message) { event.messages.create!(kind: "invitation", channels: %w[email], idempotency_key: "k1", audience: {}) }
  let(:delivery) { message.deliveries.create!(guest: guest, channel: "email", recipient: guest.email) }

  it "sends once, records the provider message id and marks the guest invited" do
    expect(delivery.deliver_now!).to be(true)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(delivery.reload.status).to eq("sent")
    expect(delivery.provider_message_id).to start_with("delivery-#{delivery.id}-")
    expect(guest.reload.invited_at).to be_present
  end

  it "never sends the same delivery twice, even if the job runs again" do
    delivery.deliver_now!
    expect(delivery.deliver_now!).to be(false)
    expect(Delivery.find(delivery.id).deliver_now!).to be(false)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "lets exactly one of two concurrent workers claim a delivery" do
    a = Delivery.find(delivery.id)
    b = Delivery.find(delivery.id)
    expect([ a.claim!, b.claim! ]).to contain_exactly(true, false)
  end

  it "marks transient failures as failed and raises so the job retries" do
    allow(Messaging::EmailGateway).to receive(:deliver).and_raise(Net::ReadTimeout)
    expect { delivery.deliver_now! }.to raise_error(Delivery::TransientError)
    expect(delivery.reload.status).to eq("failed")
    expect(delivery.attempts).to eq(1)
  end

  it "doesn't retry permanent failures" do
    allow(Messaging::EmailGateway).to receive(:deliver).and_raise(Messaging::NotConfigured, "Email is not configured")
    expect(delivery.deliver_now!).to be(false)
    expect(delivery.reload).to have_attributes(status: "failed", error_message: "Email is not configured")
  end

  it "leaves the delivery 'sending' (not retried) if recording success fails after the send" do
    allow_any_instance_of(Delivery).to receive(:mark_sent!).and_raise(ActiveRecord::ConnectionFailed)
    expect { delivery.deliver_now! }.to raise_error(ActiveRecord::ConnectionFailed)
    expect(delivery.reload.status).to eq("sending")
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    travel_to(20.minutes.from_now) { expect(delivery.reload).to be_stale }
  end

  it "is retried by the job until it succeeds" do
    calls = 0
    allow(Messaging::EmailGateway).to receive(:deliver) do
      calls += 1
      raise Errno::ECONNRESET if calls == 1

      Messaging::Receipt.new(provider: "test", message_id: "abc")
    end

    perform_enqueued_jobs { DeliveryJob.perform_later(delivery.id) }
    expect(delivery.reload).to have_attributes(status: "sent", attempts: 2)
  end
end
