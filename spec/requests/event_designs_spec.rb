require "rails_helper"

RSpec.describe "Invitation design editor", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, owner: host) }

  before { sign_in host }

  it "renders the editor with every template" do
    get edit_event_design_path(event)
    expect(response).to have_http_status(:ok)
    InvitationTemplate.all.each { |t| expect(page_text).to include(t.name) }
  end

  it "saves template, wording, fonts, colors and layout" do
    patch event_design_path(event), params: { design: {
      template: "deco-fan", headline: "Black tie", tagline: "", message: "Cocktails at 7",
      heading_font: "playfair-display", body_font: "josefin-sans", layout: "framed",
      background_color: "#14213D", text_color: "#F5E6C8", accent_color: "#D4A845", show_artwork: "1"
    } }
    expect(response).to redirect_to(event_path(event))
    design = event.reload.design_settings
    expect(design).to have_attributes(template: "deco-fan", headline: "Black tie", tagline: "", message: "Cocktails at 7",
      layout: "framed", heading_font: "playfair-display", show_artwork: true)
  end

  it "rejects invalid colors and unknown fonts without saving" do
    patch event_design_path(event), params: { design: { background_color: "url(javascript:alert(1))", heading_font: "Wingdings" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("must be a color like #A1B2C3")
    expect(event.reload.design).to eq({})
  end

  it "uploads raster artwork and can remove it" do
    patch event_design_path(event), params: { design: { photo_style: "inset" },
      artwork: fixture_file_upload("artwork.png", "image/png") }
    expect(event.reload.artwork).to be_attached

    get guest_invitation_path(create(:guest, event: event).access_token) if event.publish
    expect(response.body).to include("invite-card__photo--inset")

    patch event_design_path(event), params: { design: { photo_style: "inset" }, remove_artwork: "1" }
    expect(event.reload.artwork).not_to be_attached
  end

  it "refuses SVG uploads (they can carry scripts)" do
    patch event_design_path(event), params: { design: { template: "starlit" },
      artwork: fixture_file_upload("sneaky.svg", "image/svg+xml") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("must be a PNG, JPEG, WebP or GIF image")
    expect(event.reload.artwork).not_to be_attached
  end

  it "is not available for other hosts' events" do
    other = create(:event)
    get edit_event_design_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
