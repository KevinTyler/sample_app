require "rails_helper"

RSpec.describe "Design editor and guest RSVP in a browser", type: :system, js: true do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host, title: "Garden Party") }

  it "previews design changes live and saves them" do
    sign_in_as host
    visit edit_event_design_path(event)

    # Pick a template: the preview recolors and swaps artwork immediately
    find("label.template-option", text: "Starlit").click
    expect(css_var("#editor-card", "--card-bg").downcase).to eq("#1b1f3b")
    expect(page).to have_css("#editor-card .invite-art--starlit")

    fill_in "Headline", with: "Under the stars"
    expect(find("#editor-card .invite-card__headline")).to have_text("Under the stars")

    find("button.palette-button[title='Sea Glass']").click
    expect(css_var("#editor-card", "--card-accent").downcase).to eq("#3f9c8f")

    find("label.layout-option", text: "Framed border").click
    expect(page).to have_css("#editor-card.invite-card--framed")

    click_button "Mobile"
    expect(page).to have_css(".preview-frame[data-viewport='mobile']")

    click_button "Save design"
    expect(page).to have_content("Design saved.")
    expect(event.reload.design).to include("template" => "starlit", "headline" => "Under the stars", "layout" => "framed", "accent_color" => "#3F9C8F")
  end

  it "lets a guest RSVP on their phone-sized screen and change it later" do
    create(:event_question, event: event, prompt: "Dinner?", options: [ "Fish", "Veg" ], required: true)
    guest = create(:guest, event: event, name: "Dana Whitfield", plus_ones_allowed: 1)
    page.driver.resize(390, 844)

    visit guest_invitation_path(guest.access_token)
    expect(page).to have_content("Will you be there, Dana?")

    find("label.rsvp-choice", text: "Regretfully declines").click
    expect(page).to have_no_field("Dinner?")           # attending-only question hidden
    find("label.rsvp-choice", text: "Joyfully accepts").click
    select "2", from: "How many in your party (including you)?"
    select "Veg", from: "Dinner?"
    click_button "Send my RSVP"

    expect(page).to have_content("You're going!")
    expect(page).to have_content("party of 2")
    expect(guest.reload).to have_attributes(rsvp_status: "yes", party_size: 2)

    find("summary", text: "Change your response").click
    find("label.rsvp-choice", text: "Regretfully declines").click
    click_button "Update my RSVP"
    expect(page).to have_content("You can't make it")
    expect(guest.reload).to be_rsvp_no
  end
end
