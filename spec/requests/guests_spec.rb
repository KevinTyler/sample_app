require "rails_helper"

RSpec.describe "Guest management", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host) }

  before { sign_in host }

  it "adds a guest with normalized contact details" do
    post event_guests_path(event), params: { guest: { name: "  Lee  Park ", email: "LEE@Example.COM", phone: "+1 (555) 010-2000" } }
    guest = event.guests.sole
    expect(guest).to have_attributes(name: "Lee Park", email: "lee@example.com", phone: "+15550102000")
  end

  it "rejects email addresses without a real domain" do
    post event_guests_path(event), params: { guest: { name: "Ben", email: "ben@example" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects duplicate emails on the same event" do
    create(:guest, event: event, email: "lee@example.com")
    post event_guests_path(event), params: { guest: { name: "Lee again", email: "Lee@example.com" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("already on this guest list")
  end

  it "lets the host record an RSVP on the guest's behalf past the deadline" do
    guest = create(:guest, event: event, plus_ones_allowed: 1)
    event.update!(rsvp_deadline: 1.day.from_now)
    travel_to(2.days.from_now) do
      patch rsvp_event_guest_path(event, guest), params: { rsvp: { status: "yes", party_size: "2" } }
    end
    expect(guest.reload).to have_attributes(rsvp_status: "yes", party_size: 2)
  end

  it "resends an invitation on request, even though one was already sent" do
    guest = create(:guest, event: event)
    perform_enqueued_jobs do
      post event_invitation_send_path(event), params: { idempotency_key: SecureRandom.uuid }
      post resend_event_guest_path(event, guest), params: { idempotency_key: SecureRandom.uuid }
    end
    expect(ActionMailer::Base.deliveries.size).to eq(2)
  end

  it "removes a guest" do
    guest = create(:guest, event: event)
    expect { delete event_guest_path(event, guest) }.to change(event.guests, :count).by(-1)
  end
end
