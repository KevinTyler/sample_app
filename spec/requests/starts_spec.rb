require "rails_helper"

RSpec.describe "Make one like this", type: :request do
  let(:event) do
    create(:event, :published, title: "Maya turns thirty", design: InvitationDesign.new(InvitationTemplate.find("deco-fan").design_defaults
      .merge("message" => "Private words", "envelope" => "midnight", "liner" => "foil")).to_storage)
  end
  let(:guest) { create(:guest, event: event) }

  it "links guests from the invitation to a fresh card in the same design, after sign-up" do
    get guest_invitation_path(guest.access_token)
    cta = Nokogiri::HTML(response.body).at_css("a.host-cta")["href"]
    expect(cta).to eq(start_path(from: event.share_token))

    get cta
    expect(page_text).to include("Start from the", "Gilded Fan")
    post registration_path, params: { user: { name: "Nina New", email_address: "nina@example.com", password: "long-password-1", password_confirmation: "long-password-1" } }

    copy = User.find_by!(email_address: "nina@example.com").owned_events.sole
    expect(response).to redirect_to(edit_event_design_path(copy))
    expect(copy).to have_attributes(inspired_by_event: event, status: "draft", title: "My invitation")
    expect(copy.design).to include("template" => "deco-fan", "envelope" => "midnight", "liner" => "foil")
    expect(copy.design).not_to have_key("message")
    expect(copy.guests).to be_empty
  end

  it "starts straight away for a signed-in host, and ignores drafts and unknown tokens" do
    host = create(:user)
    sign_in host
    post start_path(from: event.share_token)
    expect(host.owned_events.sole.inspired_by_event).to eq(event)

    get start_path(from: create(:event).share_token)
    expect(response).to redirect_to(root_path)
  end
end
