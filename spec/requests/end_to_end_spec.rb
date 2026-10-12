require "rails_helper"

# The core Stage 1 flow, through the real HTTP endpoints:
# create an event → publish → invite a guest → guest RSVPs → host sees the response.
RSpec.describe "Invitation and RSVP flow", type: :request do
  it "takes a host from sign-up to seeing a guest's RSVP" do
    # Host signs up
    post registration_path, params: { user: { name: "Jordan Host", email_address: "jordan@example.com",
      password: "correct-horse-battery", password_confirmation: "correct-horse-battery" } }
    expect(response).to redirect_to(events_path)

    # Creates an event (times are entered in the event's time zone)
    post events_path, params: { event: {
      title: "Maya's 30th", host_name: "Jordan & Sam", time_zone: "America/Chicago",
      starts_at_local: 3.weeks.from_now.strftime("%Y-%m-%dT19:30"), location_name: "The Greenhouse",
      description: "Cake at 8!", capacity: "20", default_plus_ones: "1", allow_maybe: "1"
    } }
    event = Event.last
    expect(response).to redirect_to(event_path(event))
    expect(event).to be_draft
    expect(event.local(event.starts_at).strftime("%H:%M")).to eq("19:30")

    # Adds a question and a guest
    post event_questions_path(event), params: { question: { prompt: "Dinner?", kind: "choice", options_text: "Chicken\nRisotto", required: "1", applies_to: "attending" } }
    post event_guests_path(event), params: { guest: { name: "Dana Whitfield", email: "dana@example.com", plus_ones_allowed: "1", group_name: "Family" } }
    guest = event.guests.sole
    expect(guest.plus_ones_allowed).to eq(1)

    # Can't send before publishing
    post event_invitation_send_path(event), params: { idempotency_key: SecureRandom.uuid }
    expect(flash[:alert]).to include("Publish")
    expect(event.messages).to be_empty

    # Publishes and sends invitations
    post publish_event_path(event)
    expect(event.reload).to be_published

    key = SecureRandom.uuid
    perform_enqueued_jobs do
      post event_invitation_send_path(event), params: { idempotency_key: key, personal_note: "Hope you can come!" }
      # A double-submitted form (same key) must not send a second email
      post event_invitation_send_path(event), params: { idempotency_key: key }
    end
    expect(ActionMailer::Base.deliveries.size).to eq(1)

    email = ActionMailer::Base.deliveries.last
    expect(email.to).to eq([ "dana@example.com" ])
    expect(email.subject).to eq("You're invited: Maya's 30th")
    expect(email.html_part.body.to_s).to include("Hope you can come!")
    expect(email.attachments.map(&:filename)).to eq([ "maya-s-30th.ics" ])
    link = email.text_part.body.to_s[%r{http://example\.com/i/[A-Za-z0-9_-]{40}}]
    expect(link).to be_present
    expect(guest.reload.invited_at).to be_present

    # Guest (signed out, different session) opens the personal link
    delete session_path
    get link
    expect(response).to have_http_status(:ok)
    expect(page_text).to include("Maya's 30th", "Will you be there, Dana?")
    expect(guest.reload.first_viewed_at).to be_present

    # Guest RSVPs yes for two and answers the question
    question = event.questions.sole
    patch "#{link}/rsvp", params: { rsvp: { status: "yes", party_size: "2", guest_note: "So excited", answers: { question.id.to_s => "Risotto" } } }
    expect(response).to redirect_to(link)
    follow_redirect!
    expect(page_text).to include("You're going!", "party of 2", "Risotto")

    # ...then changes their mind using the same personal link
    # (required questions still apply to "maybe", so a missing answer is rejected)
    patch "#{link}/rsvp", params: { rsvp: { status: "maybe", party_size: "1" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("Please answer: Dinner?")
    patch "#{link}/rsvp", params: { rsvp: { status: "maybe", party_size: "1", answers: { question.id.to_s => "Risotto" } } }
    expect(guest.reload).to be_rsvp_maybe

    patch "#{link}/rsvp", params: { rsvp: { status: "yes", party_size: "2", answers: { question.id.to_s => "Chicken" } } }

    # Host sees the response on the dashboard
    sign_in User.find_by!(email_address: "jordan@example.com")
    get event_path(event)
    expect(page_text).to include("Dana Whitfield", "Attending", "Chicken")
    expect(event.rsvp_summary).to include(yes: 1, attending: 2)
    expect(event.activities.pluck(:action)).to include("viewed", "rsvp_submitted", "rsvp_changed")
  end
end
