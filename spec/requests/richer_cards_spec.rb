require "rails_helper"

RSpec.describe "Richer cards", type: :request do
  let(:owner) { create(:user) }
  let(:event) { create(:event, :published, owner: owner, title: "Maya turns thirty", location_name: "The Greenhouse", address: "12 Garden St, Brooklyn") }
  let(:guest) { create(:guest, event: event, name: "Dana Whitfield") }

  describe "links on the back of the card" do
    it "recognizes well-known services and labels them" do
      link = event.links.create!(url: "https://www.opentable.com/r/the-greenhouse")
      expect(link).to have_attributes(kind: "reservation", provider: "OpenTable", button_text: "Book a table on OpenTable")
      expect(event.links.create!(url: "https://www.zola.com/registry/priya-theo").button_text).to eq("See the registry on Zola")
      expect(event.links.create!(url: "https://open.spotify.com/playlist/abc", label: "Add your song").button_text).to eq("Add your song")
      expect(event.links.create!(url: "https://example.org/info").kind).to eq("other")
    end

    it "has an icon for every kind of link" do
      expect(EventLink::KINDS.values.map { |k| k[:icon] } - IconHelper::ICONS.keys).to be_empty
    end

    it "only accepts web addresses and caps the number of links" do
      expect(event.links.build(url: "javascript:alert(1)")).not_to be_valid
      expect(event.links.build(url: "ftp://example.com/x")).not_to be_valid
      EventLink::MAX_PER_EVENT.times { |i| event.links.create!(url: "https://example.com/#{i}") }
      expect(event.links.build(url: "https://example.com/more")).not_to be_valid
    end

    it "are edited in the studio and shown on the card back with directions and a ride" do
      sign_in owner
      patch event_design_path(event), params: { design: { template: "garden-arch" }, event: { show_ride_links: "1" },
        links: { "0" => { url: "https://resy.com/cities/ny/the-greenhouse", kind: "", label: "" },
                 "1" => { url: "", kind: "", label: "" } } }
      expect(response).to redirect_to(event_path(event))
      expect(event.links.sole).to have_attributes(kind: "reservation", provider: "Resy")

      get guest_invitation_path(guest.access_token)
      back = Nokogiri::HTML(response.body).at_css(".invite-back")
      expect(back.text).to include("Book a table on Resy", "The Greenhouse")
      expect(back.css("a").map { |a| a["href"] }).to include("https://resy.com/cities/ny/the-greenhouse",
        a_string_starting_with("https://m.uber.com/ul/?action=setPickup"), a_string_starting_with("https://www.google.com/maps/dir/"))
    end

    it "rejects a bad link without saving any of the design" do
      sign_in owner
      patch event_design_path(event), params: { design: { headline: "New headline" }, links: { "0" => { url: "not a url" } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(event.reload.links).to be_empty
      expect(event.design_settings.headline).not_to eq("New headline")
    end
  end

  describe "envelope, liner, stamp and backdrop" do
    it "validates choices from fixed lists and applies them to the guest page" do
      sign_in owner
      patch event_design_path(event), params: { design: { envelope: "midnight", liner: "foil", stamp: "heart", backdrop: "night" } }
      expect(event.reload.design).to include("envelope" => "midnight", "liner" => "foil", "stamp" => "heart", "backdrop" => "night")
      follow_redirect!

      get guest_invitation_path(guest.access_token)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".envelope")["data-liner"]).to eq("foil")
      expect(doc.at_css(".envelope .envelope__stamp")).to be_present
      expect(doc.at_css("body")["class"]).to include("guest-body--dark")
      expect(response.body).to include("--envelope: #1F1D3D", "--guest-backdrop: #1F1D3D")

      patch event_design_path(event), params: { design: { liner: "url(evil)" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "keeps envelope choices when switching templates" do
      sign_in owner
      patch event_design_path(event), params: { design: { liner: "check", stamp: "moon" } }
      patch event_design_path(event), params: { design: { template: "starlit" } }
      expect(event.reload.design).to include("template" => "starlit", "liner" => "check", "stamp" => "moon")
    end
  end

  describe "photo gallery" do
    let(:png) { fixture_file_upload("artwork.png", "image/png") }

    it "adds photos, shows them to guests and removes them" do
      sign_in owner
      patch event_design_path(event), params: { design: { template: "garden-arch" }, photos: [ png, fixture_file_upload("artwork.png", "image/png") ] }
      expect(event.reload.photos.count).to eq(2)

      get guest_invitation_path(guest.access_token)
      expect(Nokogiri::HTML(response.body).css(".photo-strip img").size).to eq(2)

      patch event_design_path(event), params: { design: { template: "garden-arch" }, remove_photo_ids: [ event.photos.first.id ] }
      perform_enqueued_jobs
      expect(event.reload.photos.count).to eq(1)
    end

    it "refuses non-images" do
      sign_in owner
      patch event_design_path(event), params: { design: { template: "garden-arch" }, photos: [ fixture_file_upload("sneaky.svg", "image/svg+xml") ] }
      expect(response).to have_http_status(:unprocessable_content)
      expect(event.reload.photos).to be_empty
    end
  end

  describe "save-the-dates and announcements" do
    it "sends a save-the-date without a reply form, then the real invitation to the same guests" do
      event.update!(card_type: "save_the_date")
      create(:guest, event: event, email: "dana@example.com")
      sign_in owner

      perform_enqueued_jobs { post event_invitation_send_path(event), params: { idempotency_key: "std-123456" } }
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Save the date: Maya turns thirty")
      expect(mail.text_part.body.to_s).to include("formal invitation will follow")

      guest = event.guests.sole
      get guest_invitation_path(guest.access_token)
      expect(page_text).to include("A formal invitation will follow")
      expect(page_text).not_to include("Will you be there")
      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } }
      expect(guest.reload).to be_rsvp_pending

      event.update!(card_type: "invitation")
      perform_enqueued_jobs { post event_invitation_send_path(event), params: { idempotency_key: "inv-123456" } }
      expect(ActionMailer::Base.deliveries.last.subject).to eq("You're invited: Maya turns thirty")
    end

    it "lets an announcement be published without a date" do
      draft = create(:event, owner: owner, card_type: "announcement", starts_at: nil)
      expect(draft.publish).to be(true)
    end
  end

  describe "print and install" do
    it "renders the card front and back for printing" do
      sign_in owner
      get print_event_path(event)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".print-page .invite-card, .print-page .invite-back").size).to eq(2)
    end

    it "serves a web app manifest and service worker" do
      get pwa_manifest_path(format: :json)
      expect(JSON.parse(response.body)).to include("name" => "Cordially", "start_url" => "/events", "display" => "standalone")
      get pwa_service_worker_path(format: :js)
      expect(response.body).to include("offline.html")
    end
  end

  it "offers the new templates in the studio" do
    sign_in owner
    get edit_event_design_path(event)
    expect(page_text).to include("Festival Lights", "Balloon Bunch", "Seaside", "Bubbles", "Wildflower Meadow", "Trailhead")
    InvitationTemplate.all.each { |t| expect(InvitationDesign.new(t.design_defaults)).to be_valid }
  end
end
