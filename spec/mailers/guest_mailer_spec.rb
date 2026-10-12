require "rails_helper"

RSpec.describe GuestMailer do
  let(:event) { create(:event, :published, title: "Garden Party", host_name: "The Parks") }
  let(:guest) { create(:guest, event: event, name: "Dana Whitfield") }
  let(:message) { event.messages.create!(kind: "invitation", channels: %w[email], idempotency_key: "m1", audience: {}) }
  let(:delivery) { message.deliveries.create!(guest: guest, channel: "email", recipient: guest.email) }
  let(:mail) { described_class.with(delivery: delivery).notice }

  it "addresses the guest personally with their private link" do
    expect(mail.to).to eq([ guest.email ])
    expect(mail[:from].display_names).to eq([ "The Parks via Larkspur" ])
    expect(mail.reply_to).to eq([ event.owner.email_address ])
    expect(mail.text_part.body.to_s).to include("Hi Dana", "/i/#{guest.access_token}")
  end

  it "includes one-click unsubscribe headers and a stable message id" do
    expect(mail["List-Unsubscribe"].to_s).to include("/i/#{guest.access_token}/unsubscribe")
    expect(mail["List-Unsubscribe-Post"].to_s).to eq("List-Unsubscribe=One-Click")
    expect(mail.message_id).to start_with("delivery-#{delivery.id}-")
  end

  it "attaches a calendar file" do
    expect(mail.attachments.first.mime_type).to eq("text/calendar")
  end
end
