require "rails_helper"

RSpec.describe Message do
  let(:event) { create(:event, :published) }
  let!(:dana) { create(:guest, event: event, name: "Dana", group_name: "Family") }
  let!(:lee) { create(:guest, event: event, name: "Lee", group_name: "Work") }
  let!(:no_email) { create(:guest, event: event, name: "Pat", email: nil) }

  def invitation(key: SecureRandom.uuid, **attrs)
    event.messages.create!({ kind: "invitation", channels: %w[email], audience: {}, idempotency_key: key }.merge(attrs))
  end

  describe "#dispatch!" do
    it "creates one delivery per emailable guest and enqueues them" do
      message = invitation
      expect { message.dispatch! }.to have_enqueued_job(DeliveryJob).exactly(2).times
      expect(message.deliveries.pluck(:recipient)).to contain_exactly(dana.email, lee.email)
      expect(message.reload.status).to eq("dispatched")
      expect(message.recipients_count).to eq(2)
    end

    it "is idempotent: dispatching again creates no new deliveries" do
      message = invitation
      message.dispatch!
      expect { message.dispatch! }.not_to change(Delivery, :count)
    end

    it "skips guests who already have an invitation from an earlier send" do
      invitation.dispatch!
      newcomer = create(:guest, event: event)
      second = invitation
      expect(second.recipients).to contain_exactly(newcomer)
    end

    it "does send again when the host explicitly resends to a guest" do
      invitation.dispatch!
      resend = invitation(audience: { "guest_ids" => [ dana.id ], "resend" => true })
      expect(resend.recipients).to contain_exactly(dana)
    end

    it "retries guests whose earlier invitation failed" do
      first = invitation
      first.dispatch!
      first.deliveries.find_by(guest: dana).update!(status: "failed")
      expect(invitation.recipients).to contain_exactly(dana)
    end

    it "skips guests who unsubscribed" do
      lee.update!(unsubscribed_at: Time.current)
      message = invitation
      message.dispatch!
      expect(message.deliveries.map(&:guest)).to contain_exactly(dana)
    end
  end

  describe "idempotency keys" do
    it "are unique per event so a double-submitted form can't create two sends" do
      invitation(key: "same-key-123")
      expect { invitation(key: "same-key-123") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "audiences for updates" do
    it "targets filtered guests who were invited or have responded" do
      dana.update!(invited_at: Time.current)
      lee.update!(invited_at: Time.current, rsvp_status: "yes", party_size: 1)
      create(:guest, event: event, group_name: "Family") # never invited

      update = event.messages.create!(kind: "update", subject: "Parking", body: "Use the side lot",
        channels: %w[email], idempotency_key: "u1", audience: { "groups" => [ "Family" ] })
      expect(update.recipients).to contain_exactly(dana)

      by_status = event.messages.create!(kind: "reminder", subject: "Soon!", body: "See you",
        channels: %w[email], idempotency_key: "u2", audience: { "statuses" => [ "yes" ] })
      expect(by_status.recipients).to contain_exactly(lee)
    end

    it "requires a subject and body for updates" do
      message = event.messages.new(kind: "update", channels: %w[email], idempotency_key: "u3")
      expect(message).not_to be_valid
      expect(message.errors[:subject]).to be_present
    end
  end
end
