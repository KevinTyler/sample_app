require "rails_helper"

RSpec.describe "Scheduled messages" do
  let(:event) { create(:event, :published, time_zone: "America/Denver") }
  let!(:guest) { create(:guest, event: event, invited_at: 1.day.ago) }

  def scheduled(at_local)
    event.messages.create!(kind: "reminder", subject: "Soon", body: "See you", channels: %w[email],
      idempotency_key: SecureRandom.uuid, status: "scheduled", scheduled_for_local: at_local)
  end

  it "reads the send time in the event's time zone" do
    message = scheduled(2.days.from_now.in_time_zone("America/Denver").strftime("%Y-%m-%dT09:00"))
    expect(message.scheduled_for.in_time_zone("America/Denver").hour).to eq(9)
  end

  it "must be scheduled in the future" do
    expect { scheduled(1.hour.ago.in_time_zone("America/Denver").strftime("%Y-%m-%dT%H:%M")) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "dispatches once when due, even if two workers race" do
    message = scheduled(1.hour.from_now.in_time_zone("America/Denver").strftime("%Y-%m-%dT%H:%M"))
    expect(message.dispatch_scheduled!).to be(false) # not due yet

    travel_to(2.hours.from_now) do
      copy = Message.find(message.id)
      expect([ message.dispatch_scheduled!, copy.dispatch_scheduled! ]).to contain_exactly(true, false)
      expect(message.reload.status).to eq("dispatched")
      expect(message.deliveries.count).to eq(1)
    end
  end

  it "is swept up by the recurring job" do
    message = scheduled(1.hour.from_now.in_time_zone("America/Denver").strftime("%Y-%m-%dT%H:%M"))
    travel_to(2.hours.from_now) { DispatchDueMessagesJob.perform_now }
    expect(message.reload.status).to eq("dispatched")
  end
end
