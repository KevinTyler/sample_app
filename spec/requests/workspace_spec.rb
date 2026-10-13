require "rails_helper"

RSpec.describe "Event workspace", type: :request do
  let(:owner) { create(:user, name: "Olive Owner") }
  let(:event) { create(:event, :published, owner: owner, title: "Maya turns thirty") }

  it "gives the owner every section, with the guest count in the sidebar" do
    create_list(:guest, 3, event: event)
    sign_in owner
    get event_path(event)

    nav = Nokogiri::HTML(response.body).at_css("nav.workspace__nav")
    expect(nav.css(".side-link").map { |link| link.css("span").map(&:text).join(" ") }).to eq(
      [ "Overview", "Guests 3", "Design", "Messages", "RSVP form 0", "Check-in", "Settings", "Co-hosts" ]
    )
    expect(nav.at_css(".side-link.is-active").text).to include("Overview")
    expect(response.body).to include(%(class="crumb"), "Maya turns thirty")
  end

  it "shows door staff only the door" do
    staff = create(:user)
    event.memberships.create!(user: staff, role: "checkin")
    sign_in staff
    get event_check_in_path(event)

    links = Nokogiri::HTML(response.body).css("nav.workspace__nav .side-link").map { |link| link.css("span").map(&:text).join(" ") }
    expect(links).to eq([ "Check-in" ])
    expect(response.body).not_to include("Share link")
  end

  it "filters the guest list by reply and search" do
    create(:guest, event: event, name: "Dana Whitfield", rsvp_status: "yes", party_size: 2)
    create(:guest, event: event, name: "Lee Park")
    sign_in owner

    get event_guests_path(event, status: "yes")
    expect(page_text).to include("Dana Whitfield")
    expect(page_text).not_to include("Lee Park")

    get event_guests_path(event, q: "lee")
    expect(page_text).to include("Lee Park")
    expect(page_text).not_to include("Dana Whitfield")
  end

  it "lists RSVP questions with answer tallies" do
    question = create(:event_question, event: event, prompt: "Dinner?", options: [ "Chicken", "Risotto" ])
    guest = create(:guest, event: event, rsvp_status: "yes")
    guest.rsvp_answers.create!(event_question: question, value: "Risotto")
    sign_in owner

    get event_questions_path(event)
    doc = Nokogiri::HTML(response.body)
    tally = doc.css(".question-list .tally li").map { |li| li.css("span, strong").first(2).map(&:text).join(" ") }
    expect(tally).to eq([ "Chicken 0", "Risotto 1" ])
  end

  it "offers WhatsApp and text sharing of the public link, never a personal one" do
    guest = create(:guest, event: event)
    sign_in owner
    get event_path(event)

    share = Nokogiri::HTML(response.body).at_css(".share-buttons")
    whatsapp = share.at_css("a[href^='https://wa.me/']")["href"]
    expect(CGI.unescape(whatsapp)).to include("Maya turns thirty", public_event_url(event.share_token))
    expect(share.to_html).not_to include(guest.access_token)
  end

  it "keeps the guest list off the overview for the cleaner dashboard" do
    create(:guest, event: event, name: "Dana Whitfield", email: "dana@example.com")
    sign_in owner
    get event_path(event)
    expect(response.body).not_to include("dana@example.com")
  end
end
