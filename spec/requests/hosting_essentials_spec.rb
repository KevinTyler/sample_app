require "rails_helper"

RSpec.describe "Hosting essentials", type: :request do
  let(:owner) { create(:user, name: "Olive Owner") }
  let(:event) { create(:event, :published, owner: owner, title: "Maya turns thirty") }

  describe "adults, kids and plus-one names" do
    before { event.update!(track_kids: true, ask_plus_one_names: true) }

    let(:guest) { create(:guest, event: event, name: "Dana Whitfield", plus_ones_allowed: 3) }

    it "records adults and kids separately, with the names of everyone coming" do
      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", adults: "2", kids: "1",
        plus_one_names: [ "Sam Whitfield", "Jonah Whitfield", "" ] } }

      guest.reload
      expect(guest).to have_attributes(party_size: 3, kids_count: 1, adults_count: 2, plus_one_names: [ "Sam Whitfield", "Jonah Whitfield" ])
      expect(guest.party_breakdown).to eq("2 adults, 1 kid")
      expect(event.rsvp_summary).to include(attending: 3, attending_kids: 1)

      sign_in owner
      get event_guests_path(event)
      expect(page_text).to include("2 adults, 1 kid", "with Sam Whitfield and Jonah Whitfield")
    end

    it "keeps the party within the invitation and needs an adult" do
      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", adults: "3", kids: "2" } }
      expect(response).to have_http_status(:unprocessable_content)

      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", adults: "0", kids: "2" } }
      expect(page_text).to include("at least one adult")
      expect(guest.reload).to be_rsvp_pending
    end

    it "clears kids and names when the guest declines" do
      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", adults: "1", kids: "1", plus_one_names: [ "Jonah" ] } }
      patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "no" } }
      expect(guest.reload).to have_attributes(party_size: 0, kids_count: 0, plus_one_names: [])
    end
  end

  describe "host notifications" do
    let(:guest) { create(:guest, event: event, name: "Dana Whitfield") }

    it "emails the host each reply by default" do
      perform_enqueued_jobs do
        patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } }
      end
      mail = ActionMailer::Base.deliveries.find { |m| m.to == [ owner.email_address ] }
      expect(mail.subject).to eq("Dana Whitfield is coming · Maya turns thirty")
      expect(mail.text_part.body.to_s).to include("1 attending", "/events/#{event.id}/guests")
    end

    it "sends daily-summary hosts one email for the day's replies, and nothing when set to off" do
      owner.update!(rsvp_notifications: "daily")
      editor = create(:user)
      event.memberships.create!(user: editor, role: "editor")
      editor.update!(rsvp_notifications: "off")

      perform_enqueued_jobs do
        patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } }
        patch guest_rsvp_path(create(:guest, event: event, name: "Lee Park").access_token), params: { rsvp: { status: "no" } }
      end
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).not_to include(owner.email_address, editor.email_address)

      perform_enqueued_jobs { HostNotifier.send_digests }
      digest = ActionMailer::Base.deliveries.last
      expect(digest.to).to eq([ owner.email_address ])
      expect(digest.subject).to eq("2 new replies on Cordially")
      expect(digest.text_part.body.to_s).to include("Dana Whitfield is coming", "Lee Park can't make it")

      expect { perform_enqueued_jobs { HostNotifier.send_digests } }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it "lets hosts choose in their settings" do
      sign_in owner
      patch account_path, params: { user: { name: "Olive O.", rsvp_notifications: "daily" } }
      expect(owner.reload).to have_attributes(name: "Olive O.", rsvp_notifications: "daily")
      patch account_path, params: { user: { rsvp_notifications: "hourly" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "guestbook" do
    let(:guest) { create(:guest, event: event, name: "Dana Whitfield") }

    it "lets invited guests sign it and hosts hide notes; the public page never shows it" do
      post guest_guestbook_path(guest.access_token), params: { guestbook_entry: { body: "Can't wait!" } }
      entry = event.guestbook_entries.last
      expect(entry).to have_attributes(author_name: "Dana Whitfield", body: "Can't wait!", guest: guest)

      other = create(:guest, event: event)
      get guest_invitation_path(other.access_token)
      expect(page_text).to include("Notes for", "Dana Whitfield", "Can't wait!")

      get public_event_path(event.share_token)
      expect(page_text).not_to include("Can't wait!")

      sign_in owner
      patch event_guestbook_entry_path(event, entry), params: { hidden: "1" }
      expect(entry.reload).to be_hidden
      get guest_invitation_path(other.access_token)
      expect(page_text).not_to include("Can't wait!")
    end

    it "is off when the host turns it off" do
      event.update!(guestbook_enabled: false)
      post guest_guestbook_path(guest.access_token), params: { guestbook_entry: { body: "Hi" } }
      expect(response).to have_http_status(:not_found)
    end

    it "rejects empty notes" do
      post guest_guestbook_path(guest.access_token), params: { guestbook_entry: { body: "  " } }
      expect(event.guestbook_entries.count).to eq(0)
      expect(flash[:alert]).to include("can't be empty")
    end
  end

  describe "scheduled invitations" do
    it "schedules invitations for later and sends to everyone uninvited at that time" do
      create(:guest, event: event, email: "dana@example.com")
      sign_in owner
      send_time = 2.days.from_now.in_time_zone(event.zone).change(sec: 0)
      post event_invitation_send_path(event), params: { idempotency_key: "sched-1234", send_at: "later",
        scheduled_for_local: send_time.strftime("%Y-%m-%dT%H:%M") }

      message = event.messages.find_by!(idempotency_key: "sched-1234")
      expect(message).to have_attributes(kind: "invitation", status: "scheduled", scheduled_for: send_time)
      expect(response).to redirect_to(event_messages_path(event))

      late_guest = create(:guest, event: event, email: "late@example.com")
      travel_to(send_time + 1.minute) { DispatchDueMessagesJob.perform_now }
      expect(message.reload.deliveries.map(&:guest_id)).to include(late_guest.id)
    end
  end
end
