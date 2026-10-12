require "rails_helper"

RSpec.describe "Messaging guests", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host) }
  let!(:dana) { create(:guest, event: event, name: "Dana", group_name: "Family", invited_at: 1.day.ago, rsvp_status: "yes", party_size: 1) }
  let!(:lee) { create(:guest, event: event, name: "Lee", group_name: "Work", invited_at: 1.day.ago) }
  let!(:pat) { create(:guest, event: event, name: "Pat", email: nil, phone: "+15550100", invited_at: 1.day.ago) }

  before { sign_in host }

  def compose(overrides = {})
    { idempotency_key: SecureRandom.uuid, send_at: "now",
      message: { kind: "update", subject: "Parking", body: "Use the side lot.", channels: [ "email" ], audience: {} }.deep_merge(overrides) }
  end

  it "sends an update to the chosen RSVP statuses and groups" do
    perform_enqueued_jobs do
      post event_messages_path(event), params: compose(audience: { statuses: [ "yes" ] })
    end
    message = event.messages.last
    expect(response).to redirect_to(event_message_path(event, message))
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ dana.email ] ])
    expect(ActionMailer::Base.deliveries.last.text_part.body.to_s).to include("Use the side lot.")

    get event_message_path(event, message)
    expect(page_text).to include("Dana", "Sent")
  end

  it "doesn't send twice when the form is submitted twice" do
    params = compose
    perform_enqueued_jobs { 2.times { post event_messages_path(event), params: params } }
    expect(event.messages.where(kind: "update").count).to eq(1)
    expect(ActionMailer::Base.deliveries.size).to eq(2) # Dana + Lee, once each
  end

  it "sends SMS through the configured adapter (dev outbox)" do
    perform_enqueued_jobs do
      post event_messages_path(event), params: compose(channels: [ "sms" ])
    end
    sms = OutboxItem.where(channel: "sms").sole
    expect(sms.recipient).to eq("+15550100")
    expect(sms.text_body).to include("Update about #{event.title}", "Use the side lot.", "/i/#{pat.access_token}", "Reply STOP")
  end

  it "schedules a message for later, and the host can cancel it" do
    at = 2.days.from_now.in_time_zone(event.time_zone).strftime("%Y-%m-%dT10:00")
    expect {
      post event_messages_path(event), params: compose(scheduled_for_local: at).merge(send_at: "later")
    }.to have_enqueued_job(DispatchScheduledMessageJob)
    message = event.messages.last
    expect(message).to be_scheduled
    expect(message.deliveries).to be_empty

    delete event_message_path(event, message)
    expect(Message.exists?(message.id)).to be(false)
  end

  it "re-renders with errors when the subject or body is missing" do
    post event_messages_path(event), params: compose(subject: "", body: "")
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("Subject can't be blank")
  end

  it "won't send a message that would reach nobody" do
    post event_messages_path(event), params: compose(audience: { statuses: [ "maybe" ] })
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("No one would receive this")
    expect(event.messages.where(kind: "update")).to be_empty
  end

  it "previews the audience size" do
    get audience_count_event_messages_path(event), params: { message: { channels: [ "email" ], audience: { groups: [ "Family", "Work" ] } } }
    expect(response.parsed_body).to include("reachable" => 2, "matching" => 2)
  end

  it "prefills a nudge for guests who haven't replied" do
    get new_event_message_path(event, preset: "nudge")
    expect(page_text).to include("Can you make it to #{event.title}?")
  end

  it "retries failed deliveries" do
    message = event.messages.create!(kind: "update", subject: "x", body: "y", channels: %w[email], idempotency_key: "r1", audience: {})
    delivery = message.deliveries.create!(guest: dana, channel: "email", recipient: dana.email, status: "failed")
    perform_enqueued_jobs { post retry_failed_event_message_path(event, message) }
    expect(delivery.reload.status).to eq("sent")
  end

  it "is limited to people who can message the event's guests" do
    other = create(:event, :published)
    get new_event_message_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
