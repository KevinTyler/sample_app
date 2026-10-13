require "rails_helper"

RSpec.describe "Contacts", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host) }

  it "keeps a private address book: add, edit, search, export, remove" do
    sign_in host
    post contacts_path, params: { contact: { name: "Dana Whitfield", email: "Dana@Example.com", phone: "+1 555 0100", household: "The Whitfields" } }
    contact = host.contacts.sole
    expect(contact).to have_attributes(email: "dana@example.com", household: "The Whitfields")

    post contacts_path, params: { contact: { name: "Dupe", email: "dana@example.com" } }
    expect(response).to have_http_status(:unprocessable_content)

    get contacts_path(q: "whit")
    expect(page_text).to include("Dana Whitfield")

    get export_contacts_path(format: :csv)
    expect(response.body).to include("Dana Whitfield,dana@example.com")

    other = create(:user)
    delete session_path
    sign_in other
    get edit_contact_path(contact)
    expect(response).to have_http_status(:not_found)
  end

  it "imports a vCard export and fills in gaps without overwriting" do
    host.contacts.create!(name: "Lee Park", email: "lee@example.com", phone: "+15550111")
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:Dana Whitfield
      N:Whitfield;Dana;;;
      EMAIL;type=INTERNET;type=HOME:dana@example.com
      TEL;type=CELL:+1 (555) 010-0100
      NOTE:Kids: Jonah\\, Mia
      END:VCARD
      BEGIN:VCARD
      VERSION:3.0
      FN:Lee Park
      EMAIL:lee@example.com
      TEL:+1 555 0999
      END:VCARD
    VCF
    sign_in host
    post contact_import_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(vcf), "text/vcard", original_filename: "contacts.vcf") }
    expect(flash[:notice]).to include("1 added", "1 skipped")
    expect(host.contacts.find_by!(email: "dana@example.com")).to have_attributes(name: "Dana Whitfield", phone: "+15550100100", notes: "Kids: Jonah, Mia")
    expect(host.contacts.find_by!(email: "lee@example.com").phone).to eq("+15550111")
  end

  it "imports a CSV with headers" do
    sign_in host
    post contact_import_path, params: { pasted: "First name,Last name,E-mail,Mobile,Family\nPriya,Shah,priya@example.com,555 0102,Shahs\n" }
    expect(host.contacts.sole).to have_attributes(name: "Priya Shah", email: "priya@example.com", household: "Shahs")
  end

  it "adds picked contacts to a guest list, skipping people already on it" do
    dana = host.contacts.create!(name: "Dana Whitfield", email: "dana@example.com", household: "Family")
    lee = host.contacts.create!(name: "Lee Park", email: "lee@example.com")
    create(:guest, event: event, email: "lee@example.com")
    sign_in host

    get from_contacts_event_guests_path(event)
    expect(page_text).to include("Dana Whitfield", "on the list")

    post add_contacts_event_guests_path(event), params: { contact_ids: [ dana.id, lee.id ] }
    expect(event.guests.find_by!(email: "dana@example.com")).to have_attributes(name: "Dana Whitfield", group_name: "Family")
    expect(flash[:notice]).to include("Added 1 guest", "1 already on the list")
  end

  it "copies another event's list fresh, but never one the user can't see contacts for" do
    old = create(:event, :published, owner: host, title: "Last year")
    create(:guest, event: old, name: "Dana Whitfield", email: "dana@example.com", rsvp_status: "yes", party_size: 2)
    sign_in host
    post add_contacts_event_guests_path(event), params: { source_event_id: old.id }
    copied = event.guests.sole
    expect(copied).to have_attributes(name: "Dana Whitfield", rsvp_status: "pending", party_size: 0)
    expect(copied.token_key).not_to eq(old.guests.sole.token_key)

    staffed = create(:event, :published, title: "Door only")
    staffed.memberships.create!(user: host, role: "checkin")
    create(:guest, event: staffed, email: "secret@example.com")
    post add_contacts_event_guests_path(event), params: { source_event_id: staffed.id }
    expect(event.guests.where(email: "secret@example.com")).to be_empty
  end

  it "saves new guests to contacts when asked" do
    sign_in host
    post event_guests_path(event), params: { guest: { name: "Sam Moreno", email: "sam@example.com" }, save_contact: "1" }
    expect(host.contacts.find_by(email: "sam@example.com")&.name).to eq("Sam Moreno")
    post event_guests_path(event), params: { guest: { name: "No Save", email: "nosave@example.com" } }
    expect(host.contacts.find_by(email: "nosave@example.com")).to be_nil
  end
end
