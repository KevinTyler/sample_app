require "rails_helper"

RSpec.describe "Switching from Paperless Post", type: :request do
  let(:host) { create(:user, name: "Jordan Reyes") }
  let(:export) do
    xlsx_from([
      [ "Guest list: Maya turns thirty" ],
      [ "Name", "Email", "Mobile", "Status", "# Attending", "Kids", "Group", "Address 1", "City", "Message", "Table" ],
      [ "Dana Whitfield", "dana@example.com", "(555) 010-0100", "Attending", 3, 1, "Family", "12 Garden St", "Brooklyn", "Can't wait!", "4" ],
      [ "Lee Park", "lee@example.com", nil, "Not attending", 0, nil, "Work", nil, nil, nil, nil ],
      [ "Sam Ortiz", "not-an-email", "555 010 0102", "No reply", nil, nil, "Work", nil, nil, nil, nil ]
    ])
  end

  def upload(data = export, filename: "Mayas-30th-guest-list.xlsx", from: "switch")
    post contact_imports_path, params: { from: from, file: Rack::Test::UploadedFile.new(StringIO.new(data),
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: filename) }
  end

  before { sign_in host }

  it "brings a guest list over with its replies and recreates the event as a draft" do
    get switch_path
    expect(page_text).to include("Bring", "everything", "Export spreadsheet", "Your usual settings")

    upload
    import = host.contact_imports.sole
    expect(response).to redirect_to(contact_import_path(import, from: "switch"))
    follow_redirect!
    expect(page_text).to include("Maya turns thirty", "Replies come too", "1 yes", "1 no", "1 not yet", "Not brought in: Table", "Recreate the event")
    expect(host.contacts.count).to eq(0) # nothing saved before the host says so

    post apply_contact_import_path(import), params: { mode: "new_event", title: "Maya turns thirty", from: "switch" }
    event = host.owned_events.sole
    expect(response).to redirect_to(event_path(event))
    expect(flash[:notice]).to include("Brought in 3 people", "3 on the guest list", "2 replies kept")
    expect(event).to have_attributes(title: "Maya turns thirty", status: "draft", host_name: "Jordan Reyes", track_kids: true)

    dana = event.guests.find_by!(email: "dana@example.com")
    expect(dana).to have_attributes(rsvp_status: "yes", party_size: 3, kids_count: 1, plus_ones_allowed: 2, group_name: "Family",
      phone: "+15550100100", guest_note: "Can't wait!", source: "import")
    expect(event.guests.find_by!(name: "Lee Park")).to have_attributes(rsvp_status: "no", party_size: 0)
    expect(event.guests.find_by!(name: "Sam Ortiz")).to have_attributes(rsvp_status: "pending", email: nil, phone: "+15550100102")

    expect(host.contacts.find_by!(email: "dana@example.com")).to have_attributes(household: "Family", mailing_address: "12 Garden St\nBrooklyn")
    expect(host.reload.switched_from).to eq("paperless_post")
    expect(import.reload).to have_attributes(status: "completed", sheet: nil)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "fills in contacts without overwriting, and adds people to an existing guest list" do
    host.contacts.create!(name: "Dana W", email: "dana@example.com", phone: "+15550109999")
    event = create(:event, owner: host)
    create(:guest, event: event, email: "lee@example.com")
    upload

    post apply_contact_import_path(host.contact_imports.sole), params: { mode: "event", event_id: event.id }
    expect(host.contacts.find_by!(email: "dana@example.com")).to have_attributes(name: "Dana W", phone: "+15550109999", household: "Family")
    expect(event.guests.count).to eq(3)
    expect(event.guests.where(email: "lee@example.com").count).to eq(1)
    expect(event.guests.pluck(:name)).to include("Dana Whitfield", "Sam Ortiz")
    expect(flash[:notice]).to include("2 on the guest list")
  end

  it "lets the host fix what a column means before bringing anyone in" do
    upload(xlsx_from([ [ "Who", "Reach" ], [ "Dana Whitfield", "dana@example.com" ] ]), filename: "list.xlsx", from: nil)
    import = host.contact_imports.sole
    patch contact_import_path(import), params: { mapping: { "0" => "name", "1" => "email" } }
    post apply_contact_import_path(import), params: { mode: "contacts" }
    expect(host.contacts.sole).to have_attributes(name: "Dana Whitfield", email: "dana@example.com")
  end

  it "explains files it can't read and keeps other hosts' imports private" do
    upload("PK\x03\x04garbage", filename: "broken.xlsx")
    expect(response).to redirect_to(switch_path)
    expect(flash[:alert]).to include("Excel")

    other = create(:user)
    theirs = ContactImport.read!(other, "Name,Email\nDana,dana@example.com\n")
    get contact_import_path(theirs)
    expect(response).to have_http_status(:not_found)
    post apply_contact_import_path(theirs), params: { mode: "contacts" }
    expect(response).to have_http_status(:not_found)
    expect(other.contacts.count).to eq(0)
  end

  it "won't add people to an event the host can't manage" do
    upload
    stranger_event = create(:event)
    post apply_contact_import_path(host.contact_imports.sole), params: { mode: "event", event_id: stranger_event.id }
    expect(stranger_event.guests.count).to eq(0)
    expect(flash[:alert]).to include("Choose an event")
  end

  it "saves the host's usual settings and starts every new event with them" do
    patch account_path(return_to: "switch"), params: { user: { default_host_name: "The Reyes Family", time_zone: "America/Chicago",
      default_track_kids: "1", default_allow_maybe: "0", default_plus_ones: "2", default_auto_nudge: "1", phone_country_code: "44" } }
    expect(response).to redirect_to(switch_path)

    get new_event_path
    expect(page_text).to include('value="The Reyes Family"')

    post events_path, params: { event: { title: "Supper club", host_name: "The Reyes Family", time_zone: "America/Chicago" } }
    expect(host.owned_events.sole.title).to eq("Supper club")
    expect(host.reload.event_defaults).to include(host_name: "The Reyes Family", track_kids: true, allow_maybe: false, default_plus_ones: 2, auto_nudge: true)
  end

  it "only texts the host once they've connected a phone" do
    patch account_path, params: { user: { agent_reach: "text" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("needs a connected phone")
  end
end
