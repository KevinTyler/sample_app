require "rails_helper"

RSpec.describe "Bulk guest tools", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host) }

  before { sign_in host }

  describe "import" do
    it "previews a CSV upload and imports on confirmation" do
      file = Rack::Test::UploadedFile.new(StringIO.new("Name,Email,Group\nDana,dana@example.com,Family\nBad,nope,\n"), "text/csv", original_filename: "list.csv")
      post event_guest_imports_path(event), params: { file: file }
      import = event.guest_imports.last
      expect(response).to redirect_to(event_guest_import_path(event, import))

      follow_redirect!
      expect(page_text).to include("list.csv", "Import 1 guest", "Fix needed", "Email is invalid")
      expect(event.guests.count).to eq(0)

      patch confirm_event_guest_import_path(event, import)
      expect(event.guests.pluck(:name)).to eq([ "Dana" ])
      expect(flash[:notice]).to include("1 added")

      patch confirm_event_guest_import_path(event, import) # double submit
      expect(event.guests.count).to eq(1)
    end

    it "accepts a pasted list" do
      post event_guest_imports_path(event), params: { pasted: "Lee Park, lee@example.com\nSam, sam@example.com" }
      expect(event.guest_imports.last.counts[:new]).to eq(2)
    end

    it "discards an import and its data" do
      post event_guest_imports_path(event), params: { pasted: "Lee, lee@example.com" }
      import = event.guest_imports.last
      delete event_guest_import_path(event, import)
      expect(GuestImport.exists?(import.id)).to be(false)
    end

    it "offers a template" do
      get template_event_guest_imports_path(event)
      expect(response.body).to start_with("Name,Email,Phone,Group,Plus ones,Notes")
    end
  end

  describe "export" do
    it "exports the guest list with answers, guarding against formula injection" do
      question = create(:event_question, event: event, prompt: "Dinner?", options: %w[Fish Veg])
      guest = create(:guest, event: event, name: "=cmd|' /C calc'!A0", rsvp_status: "yes", party_size: 2)
      guest.rsvp_answers.create!(event_question: question, value: "Veg")

      get export_event_guests_path(event, format: :csv)
      expect(response.media_type).to eq("text/csv")
      rows = CSV.parse(response.body)
      expect(rows.first).to include("Name", "Email", "RSVP", "Dinner?")
      expect(rows.second.first).to eq("'=cmd|' /C calc'!A0")
      expect(rows.second).to include("Attending", "2", "Veg")
    end
  end

  describe "bulk actions" do
    let!(:dana) { create(:guest, event: event, name: "Dana") }
    let!(:lee) { create(:guest, event: event, name: "Lee") }

    it "sets a group for the selected guests" do
      post bulk_event_guests_path(event), params: { guest_ids: [ dana.id, lee.id ], bulk_action: "group", group_name: " College  friends " }
      expect(event.guests.pluck(:group_name).uniq).to eq([ "College friends" ])
    end

    it "invites only the selected guests, once" do
      key = SecureRandom.uuid
      perform_enqueued_jobs do
        2.times { post bulk_event_guests_path(event), params: { guest_ids: [ dana.id ], bulk_action: "invite", idempotency_key: key } }
      end
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ dana.email ] ])
    end

    it "removes the selected guests and ignores ids from other events" do
      outsider = create(:guest)
      post bulk_event_guests_path(event), params: { guest_ids: [ dana.id, outsider.id ], bulk_action: "remove" }
      expect(event.guests.pluck(:name)).to eq([ "Lee" ])
      expect(Guest.exists?(outsider.id)).to be(true)
    end

    it "requires a selection" do
      post bulk_event_guests_path(event), params: { bulk_action: "remove" }
      expect(flash[:alert]).to include("Select at least one guest")
    end
  end

  it "paginates long guest lists" do
    create_list(:guest, EventsController::GUESTS_PER_PAGE + 5, event: event)
    get event_path(event, page: 2)
    expect(page_text).to include("Page 2 of 2")
  end
end
