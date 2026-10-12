require "rails_helper"

RSpec.describe "Co-hosts", type: :request do
  let(:owner) { create(:user, name: "Olive Owner") }
  let(:event) { create(:event, :published, owner: owner) }
  let(:friend) { create(:user, name: "Cory Cohost", email_address: "cory@example.com") }

  def invite(email:, role: "editor")
    sign_in owner
    perform_enqueued_jobs do
      post event_cohosts_path(event), params: { cohost_invitation: { email: email, role: role } }
    end
    delete session_path
    ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://example\.com/cohost-invites/\S+}]
  end

  it "invites by email; the invited account accepts and gets access to the event" do
    link = invite(email: "Cory@Example.com")
    expect(link).to be_present
    expect(CohostInvitation.last.token_digest).not_to include(link.split("/").last) # only a digest is stored

    get link
    expect(page_text).to include("Sign in or create an account")

    sign_in friend
    get link
    expect(page_text).to include("Accept invitation")
    post link
    expect(response).to redirect_to(event_path(event))
    expect(event.role_for(friend)).to eq("editor")

    post link # single use
    expect(event.memberships.count).to eq(1)
    expect(flash[:alert]).to include("can't be accepted")
  end

  it "refuses an invitation accepted by a different account" do
    link = invite(email: "someone-else@example.com")
    sign_in friend
    post link
    expect(event.role_for(friend)).to be_nil
  end

  it "expires invitations" do
    link = invite(email: "cory@example.com")
    sign_in friend
    travel_to(15.days.from_now) do
      post link
      expect(event.role_for(friend)).to be_nil
    end
  end

  describe "permissions" do
    let(:guest) { create(:guest, event: event) }

    it "lets an editor work on the event but not cancel, delete or manage co-hosts" do
      event.memberships.create!(user: friend, role: "editor")
      sign_in friend

      get events_path
      expect(page_text).to include(event.title, "Co-host")
      patch event_path(event), params: { event: { title: "Renamed by co-host" } }
      expect(event.reload.title).to eq("Renamed by co-host")
      post event_guests_path(event), params: { guest: { name: "Added by co-host" } }
      expect(event.guests.pluck(:name)).to include("Added by co-host")

      post cancel_event_path(event)
      expect(event.reload).to be_published
      delete event_path(event)
      expect(Event.exists?(event.id)).to be(true)
      get event_cohosts_path(event)
      expect(response).to redirect_to(event_path(event))
      expect(flash[:alert]).to include("permission")
    end

    it "limits door staff to check-in" do
      event.memberships.create!(user: friend, role: "checkin")
      guest
      sign_in friend

      get event_path(event)
      expect(response).to redirect_to(event_check_in_path(event))
      get export_event_guests_path(event, format: :csv)
      expect(response).to have_http_status(:forbidden)
      get edit_event_guest_path(event, guest)
      expect(response).to redirect_to(event_path(event))
      get new_event_message_path(event)
      expect(response).to redirect_to(event_path(event))

      get event_check_in_path(event, all: "1")
      expect(response).to have_http_status(:ok)
      expect(page_text).to include(guest.name)
      expect(page_text).not_to include(guest.email, guest.access_token)
    end

    it "lets the owner remove a co-host, and a co-host leave" do
      membership = event.memberships.create!(user: friend, role: "editor")
      sign_in friend
      delete leave_event_cohosts_path(event)
      expect(event.role_for(friend)).to be_nil

      membership = event.memberships.create!(user: friend, role: "editor")
      delete session_path
      sign_in owner
      delete event_cohost_path(event, membership)
      expect(EventMembership.exists?(membership.id)).to be(false)
    end
  end
end
