require "rails_helper"

RSpec.describe "Guest invitation pages", type: :request do
  let(:event) { create(:event, :published, capacity: 3) }
  let(:guest) { create(:guest, event: event, plus_ones_allowed: 2) }
  let(:token) { guest.access_token }

  it "shows the invitation with privacy headers" do
    get guest_invitation_path(token)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(response.headers["Referrer-Policy"]).to eq("same-origin")
    expect(page_text).to include('<meta name="robots" content="noindex, nofollow">')
  end

  it "returns a friendly 404 for unknown or forged tokens" do
    get guest_invitation_path(guest.token_key + ("x" * 24))
    expect(response).to have_http_status(:not_found)
    expect(page_text).to include("couldn't find that invitation")
  end

  it "does not show draft events to guests" do
    draft_guest = create(:guest, event: create(:event))
    get guest_invitation_path(draft_guest.access_token)
    expect(response).to have_http_status(:not_found)
  end

  it "re-renders the form with an error when the event is full" do
    create(:guest, event: event, rsvp_status: "yes", party_size: 3)
    patch guest_rsvp_path(token), params: { rsvp: { status: "yes", party_size: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("this event is full")
    expect(guest.reload).to be_rsvp_pending
  end

  it "only lets a guest change their own RSVP" do
    other = create(:guest, event: event)
    patch guest_rsvp_path(token), params: { rsvp: { status: "no" }, guest_id: other.id }
    expect(guest.reload).to be_rsvp_no
    expect(other.reload).to be_rsvp_pending
  end

  it "shows a cancelled event and closes RSVPs" do
    event.cancel(note: "Rain")
    get guest_invitation_path(token)
    expect(page_text).to include("This event has been cancelled", "Rain")
    patch guest_rsvp_path(token), params: { rsvp: { status: "yes", party_size: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "downloads a calendar file" do
    get guest_calendar_path(token)
    expect(response.media_type).to eq("text/calendar")
    expect(page_text).to include("BEGIN:VEVENT", "URL:http://www.example.com/i/#{token}")
  end

  it "supports one-click unsubscribe without a CSRF token" do
    post guest_unsubscribe_path(token), params: { "List-Unsubscribe" => "One-Click" }
    expect(guest.reload).to be_unsubscribed
  end

  it "shows updates the host sent to this guest" do
    guest.update!(invited_at: Time.current)
    update = event.messages.create!(kind: "update", subject: "New venue", body: "We moved next door.",
      channels: %w[email], idempotency_key: "upd-1", audience: {})
    update.dispatch!
    get guest_invitation_path(token)
    expect(page_text).to include("Updates from the host", "New venue", "We moved next door.")
  end

  it "doesn't count the host opening a guest's link as a guest view" do
    post session_path, params: { email_address: event.owner.email_address, password: "correct-horse-battery" }
    get guest_invitation_path(token)
    expect(guest.reload.first_viewed_at).to be_nil
  end
end
