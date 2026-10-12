require "rails_helper"

# The test environment uses a null cache, so these specs simulate a client that has already used
# up its allowance by stubbing the counter that Rails' rate limiter increments.
RSpec.describe "Rate limits", type: :request do
  def exhaust_limits!
    allow(ActionController::Base.cache_store).to receive(:increment).and_return(10_000)
  end

  it "throttles sign-in attempts" do
    exhaust_limits!
    post session_path, params: { email_address: "a@example.com", password: "nope-nope-nope" }
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("Try again later.")
  end

  it "throttles RSVP submissions per guest link" do
    guest = create(:guest, event: create(:event, :published))
    exhaust_limits!
    patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } }
    expect(flash[:alert]).to include("Too many attempts")
    expect(guest.reload).to be_rsvp_pending
  end

  it "throttles open RSVPs through the share link" do
    event = create(:event, :published, allow_link_rsvp: true)
    exhaust_limits!
    post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "A", email: "a@example.com", status: "yes", party_size: "1" } }
    expect(event.guests.count).to eq(0)
    expect(flash[:alert]).to include("Too many RSVPs")
  end
end
