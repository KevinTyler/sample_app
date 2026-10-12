require "rails_helper"

RSpec.describe "Check-in", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host) }
  let!(:dana) { create(:guest, event: event, name: "Dana Whitfield", plus_ones_allowed: 2, rsvp_status: "yes", party_size: 3) }
  let!(:lee) { create(:guest, event: event, name: "Lee Park", rsvp_status: "no") }

  before { sign_in host }

  it "lists attending guests, checks a party in and can undo it" do
    get event_check_in_path(event)
    expect(page_text).to include("Dana Whitfield")
    expect(page_text).not_to include("Lee Park")

    post event_check_in_guest_path(event, dana), params: { count: 2 }
    expect(dana.reload).to have_attributes(checked_in_count: 2)
    expect(dana.checked_in_at).to be_present
    get event_check_in_path(event)
    expect(page_text).to include("arrived")

    delete event_check_in_guest_path(event, dana)
    expect(dana.reload.checked_in_at).to be_nil
  end

  it "never checks in more people than the party allows" do
    post event_check_in_guest_path(event, dana), params: { count: 50 }
    expect(dana.reload.checked_in_count).to eq(3)
  end

  it "opens a guest from their QR pass code, which differs from their RSVP link" do
    code = dana.check_in_code
    expect(code).not_to include(dana.access_token)
    get event_check_in_scan_path(event, code: code)
    expect(page_text).to include("Dana Whitfield", "Check in")

    get event_check_in_scan_path(event, code: "#{dana.id}-forgedforged")
    expect(response).to have_http_status(:not_found)

    other_event_guest = create(:guest, rsvp_status: "yes", party_size: 1)
    get event_check_in_scan_path(event, code: other_event_guest.check_in_code)
    expect(response).to have_http_status(:not_found)
  end

  it "shows attending guests their QR pass" do
    delete session_path
    get guest_invitation_path(dana.access_token)
    expect(page_text).to include("Your check-in pass")
    expect(response.body).to include("data:image/png;base64,")
  end
end
