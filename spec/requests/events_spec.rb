require "rails_helper"

RSpec.describe "Events", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, owner: host) }

  it "requires signing in" do
    get events_path
    expect(response).to redirect_to(new_session_path)
  end

  context "when signed in" do
    before { sign_in host }

    it "lists and shows the host's events" do
      event
      get events_path
      expect(page_text).to include("Maya's Birthday")
      get event_path(event)
      expect(response).to have_http_status(:ok)
    end

    it "doesn't reveal other hosts' events" do
      other = create(:event, title: "Secret soirée")
      get event_path(other)
      expect(response).to have_http_status(:not_found)
      patch event_path(other), params: { event: { title: "Hijacked" } }
      expect(response).to have_http_status(:not_found)
      expect(other.reload.title).to eq("Secret soirée")
    end

    it "re-renders the form with errors for invalid input" do
      post events_path, params: { event: { title: "", time_zone: "America/New_York" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(page_text).to include("Title can't be blank")
    end

    it "edits an event" do
      patch event_path(event), params: { event: { title: "Maya's 31st", video_url: "https://meet.example.com/x" } }
      expect(event.reload.title).to eq("Maya's 31st")
    end

    it "bumps the calendar sequence when a published event's time changes" do
      event.publish
      expect {
        patch event_path(event), params: { event: { starts_at_local: 4.weeks.from_now.strftime("%Y-%m-%dT18:00") } }
      }.to change { event.reload.calendar_sequence }.by(1)
    end

    it "publishes, then cancels and notifies invited guests" do
      post publish_event_path(event)
      expect(event.reload).to be_published

      invited = create(:guest, event: event, invited_at: 1.day.ago)
      create(:guest, event: event) # never invited: not told about the cancellation

      perform_enqueued_jobs do
        post cancel_event_path(event), params: { cancellation_note: "So sorry!", notify_guests: "1" }
      end
      expect(event.reload).to be_cancelled
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ invited.email ] ])
      expect(ActionMailer::Base.deliveries.last.subject).to eq("Cancelled: Maya's Birthday")
    end

    it "duplicates an event with its guests" do
      create(:guest, event: event, name: "Dana")
      post duplicate_event_path(event), params: { include_guests: "1" }
      copy = Event.order(:id).last
      expect(copy).not_to eq(event)
      expect(copy.guests.pluck(:name)).to eq([ "Dana" ])
      expect(response).to redirect_to(edit_event_path(copy))
    end

    it "deletes an event and its guest data" do
      create(:guest, event: event)
      expect { delete event_path(event) }.to change(Guest, :count).by(-1)
      expect(Event.exists?(event.id)).to be(false)
    end

    it "shows a guest preview without recording views" do
      get preview_event_path(event)
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Preview")
    end
  end
end
