require "rails_helper"

RSpec.describe "Public share link", type: :request do
  let(:event) { create(:event, :published, allow_link_rsvp: true, default_plus_ones: 1, video_url: "https://meet.example.com/secret-room") }
  let(:path) { public_event_path(event.share_token) }

  it "shows the invitation without guest data or the private video link" do
    create(:guest, event: event, name: "Private Person")
    get path
    expect(response).to have_http_status(:ok)
    expect(page_text).to include(event.title, "Will you be there?")
    expect(page_text).not_to include("Private Person", "secret-room")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
  end

  it "adds a new guest with their RSVP and emails them a personal link" do
    perform_enqueued_jobs do
      post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "Robin Lake", email: "Robin@Example.com", status: "yes", party_size: "2" } }
    end
    guest = event.guests.find_by!(email: "robin@example.com")
    expect(guest).to have_attributes(source: "link", rsvp_status: "yes", party_size: 2)
    expect(response).to redirect_to(guest_invitation_path(guest.access_token))
    mail = ActionMailer::Base.deliveries.select { |m| m.to == [ "robin@example.com" ] }.sole
    expect(mail.subject).to eq("Your RSVP link: #{event.title}")
    expect(mail.text_part.body.to_s).to include(guest.access_token)
    expect(ActionMailer::Base.deliveries.map(&:to)).to include([ event.owner.email_address ]) # host hears about the reply
  end

  it "never changes an existing guest's RSVP; it emails them their own link instead (throttled)" do
    guest = create(:guest, event: event, email: "dana@example.com", rsvp_status: "no", party_size: 0)
    perform_enqueued_jobs do
      2.times do
        post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "Impostor", email: "dana@example.com", status: "yes", party_size: "2" } }
      end
    end
    expect(guest.reload).to have_attributes(rsvp_status: "no", name: guest.name)
    expect(response).to redirect_to(path)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "dana@example.com" ] ])
  end

  it "validates name, email and RSVP rules" do
    event.update!(capacity: 1)
    post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "", email: "nope", status: "yes", party_size: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
    post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "Al", email: "al@example.com", status: "yes", party_size: "2" } }
    expect(page_text).to include("Only 1 spot left")
    expect(event.guests.count).to eq(0)
  end

  it "doesn't accept RSVPs when the host keeps the event invitation-only" do
    event.update!(allow_link_rsvp: false)
    post public_event_rsvp_path(event.share_token), params: { rsvp: { name: "Al", email: "al@example.com", status: "yes", party_size: "1" } }
    expect(event.guests.count).to eq(0)
    follow_redirect!
    expect(page_text).to include("invitation-only")
  end

  it "stops working when the host regenerates the link" do
    old_token = event.share_token
    sign_in event.owner
    post regenerate_share_link_event_path(event)
    get public_event_path(old_token)
    expect(response).to have_http_status(:not_found)
  end

  it "hides drafts" do
    draft = create(:event)
    get public_event_path(draft.share_token)
    expect(response).to have_http_status(:not_found)
  end

  it "offers a calendar file" do
    get public_event_calendar_path(event.share_token)
    expect(response.media_type).to eq("text/calendar")
  end
end
