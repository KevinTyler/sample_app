require "rails_helper"

RSpec.describe Assistant::CheckIn do
  include ActionMailer::TestHelper

  let(:host) { create(:user, name: "Jordan Reyes") }

  # An invitation that went out to these guests.
  def invite!(event, guests, status: "sent")
    message = event.messages.create!(kind: "invitation", channels: %w[email], idempotency_key: "inv-#{SecureRandom.hex(3)}", audience: {}, status: "dispatched", dispatched_at: 5.days.ago)
    guests.each do |g|
      message.deliveries.create!(guest: g, channel: "email", recipient: g.email || "x@example.com", status: status)
      g.update_column(:invited_at, 5.days.ago) unless status == "bounced"
    end
  end

  def run = described_class.new(host).run

  describe "noticing what needs the host" do
    it "proposes nudging invited guests who haven't replied as the deadline nears, once" do
      event = create(:event, :published, owner: host, rsvp_deadline: 3.days.from_now, starts_at: 10.days.from_now)
      pending = create_list(:guest, 2, event: event)
      replied = create(:guest, event: event, rsvp_status: "yes")
      invite!(event, pending + [ replied ])

      proposal = run.sole
      expect(proposal).to have_attributes(kind: "nudge_pending", event: event, action_label: "Send the nudge")
      expect(proposal.title).to eq("2 guests haven’t replied to Maya's Birthday")
      expect(run).to be_empty # same situation, no second proposal
    end

    it "leaves it alone when automatic nudges are on or a reminder just went out" do
      event = create(:event, :published, owner: host, rsvp_deadline: 3.days.from_now, auto_nudge: true)
      invite!(event, [ create(:guest, event: event) ])
      expect(run).to be_empty
    end

    it "offers to send a draft that's coming up, a day-before reminder, and thank-yous afterwards" do
      draft = create(:event, owner: host, title: "Book club", starts_at: 6.days.from_now, created_at: 3.days.ago)
      create(:guest, event: draft)
      tomorrow = create(:event, :published, owner: host, title: "Picnic", starts_at: 26.hours.from_now)
      create(:guest, event: tomorrow, rsvp_status: "yes")
      past = create(:event, :published, owner: host, title: "Jonah's 5th", starts_at: 2.days.ago)
      create(:guest, event: past, rsvp_status: "yes")

      expect(run.map { |p| [ p.kind, p.event.title ] }).to contain_exactly(
        [ "send_draft", "Book club" ], [ "day_before", "Picnic" ], [ "thank_yous", "Jonah's 5th" ])
    end

    it "offers to text guests whose invitation email bounced, or asks for better details" do
      event = create(:event, :published, owner: host)
      with_phone = create(:guest, event: event, phone: "+15550100100")
      without = create(:guest, event: event)
      invite!(event, [ with_phone ], status: "bounced")
      expect(run.sole).to have_attributes(kind: "text_instead", payload: { "guest_ids" => [ with_phone.id ] })

      other = create(:event, :published, owner: host, title: "Supper")
      invite!(other, [ create(:guest, event: other) ], status: "bounced")
      expect(run.sole).to have_attributes(kind: "fix_contacts", action_label: nil)
      expect(without).to be_present
    end
  end

  describe "telling the host" do
    let(:event) { create(:event, :published, owner: host, rsvp_deadline: 3.days.from_now) }

    before { invite!(event, [ create(:guest, event: event) ]) }

    it "posts it in the web conversation and emails them by default" do
      assert_enqueued_emails(1) { run }
      web = AssistantConversation.find_by!(channel: "web", user: host)
      expect(web.messages.last).to have_attributes(direction: "out", cards: [ { "type" => "proposal", "proposal_id" => host.agent_proposals.sole.id } ])
      expect(web.messages.last.body).to be_blank # shown as a card on the web
      expect(host.agent_proposals.sole.pitch).to include("1 guest hasn’t replied to Maya's Birthday. Replies close", "friendly nudge")
    end

    it "texts them instead once their phone is connected, and a YES carries it out" do
      phone = AssistantConversation.create!(channel: "sms", address: "+15550177777", user: host, last_inbound_at: 1.day.ago)
      host.update!(agent_reach: "text")
      assert_no_enqueued_emails { run }
      expect(phone.messages.last.body).to include("hasn’t replied", "Reply YES")

      Assistant::Inbound.receive(channel: "sms", address: "+15550177777", body: "yes please", reply_now: true)
      expect(phone.messages.last.body).to include("Sent a friendly nudge to 1 guest")
      reminder = event.messages.find_by!(kind: "reminder")
      expect(reminder.deliveries.count).to eq(1)
      expect(host.agent_proposals.sole.status).to eq("done")
    end

    it "takes no for an answer" do
      phone = AssistantConversation.create!(channel: "sms", address: "+15550177777", user: host, last_inbound_at: 1.day.ago)
      host.update!(agent_reach: "text")
      run
      Assistant::Inbound.receive(channel: "sms", address: "+15550177777", body: "not now", reply_now: true)
      expect(host.agent_proposals.sole.status).to eq("dismissed")
      expect(event.messages.where(kind: "reminder")).to be_empty
      expect(phone.messages.last.body).to include("leave that")
    end
  end

  describe "approving on the web", type: :request do
    let(:event) { create(:event, :published, owner: host, rsvp_deadline: 3.days.from_now) }

    before do
      invite!(event, create_list(:guest, 2, event: event))
      sign_in host
    end

    it "carries out the proposal once, as the host, and reports back" do
      proposal = run.sole
      get agent_path
      expect(page_text).to include("Needs you · 1", "Send the nudge")

      post approve_agent_proposal_path(proposal)
      expect(response).to redirect_to(agent_path(anchor: "latest"))
      expect(event.messages.find_by!(kind: "reminder").recipients_count).to eq(2)
      expect(AssistantConversation.find_by!(channel: "web", user: host).messages.last.body).to include("Sent a friendly nudge to 2 guests")

      post approve_agent_proposal_path(proposal)
      expect(event.messages.where(kind: "reminder").count).to eq(1)
      expect(AssistantConversation.find_by!(channel: "web", user: host).messages.last.body).to include("already been taken care of")
    end

    it "doesn't let anyone else approve it" do
      proposal = run.sole
      sign_in create(:user)
      post approve_agent_proposal_path(proposal)
      expect(response).to have_http_status(:not_found)
      expect(proposal.reload.status).to eq("pending")
    end
  end

  it "expires proposals that no longer make sense" do
    event = create(:event, :published, owner: host)
    stale = host.agent_proposals.create!(event: event, kind: "day_before", dedupe_key: "x", title: "Tomorrow", expires_at: 1.hour.ago)
    described_class.run_all
    expect(stale.reload.status).to eq("expired")
  end

  it "runs from the hourly job" do
    event = create(:event, :published, owner: host, rsvp_deadline: 3.days.from_now)
    invite!(event, [ create(:guest, event: event) ])
    expect { AgentCheckInJob.perform_now }.to change(AgentProposal, :count).by(1)
  end
end
