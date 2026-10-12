require "rails_helper"

RSpec.describe RsvpSubmission do
  let(:event) { create(:event, :published) }
  let(:guest) { create(:guest, event: event, plus_ones_allowed: 2) }

  def submit(on: guest, **attrs)
    described_class.new(guest: on, **attrs).tap(&:save)
  end

  it "records a yes with party size and timestamps" do
    rsvp = submit(status: "yes", party_size: 3)
    expect(rsvp.errors).to be_empty
    expect(guest.reload).to be_rsvp_yes
    expect(guest.party_size).to eq(3)
    expect(guest.responded_at).to be_present
    expect(event.activities.last.action).to eq("rsvp_submitted")
  end

  it "stores a party size of zero when declining" do
    submit(status: "no", party_size: 3)
    expect(guest.reload).to be_rsvp_no
    expect(guest.party_size).to eq(0)
  end

  it "lets the guest change their answer and logs it as a change" do
    submit(status: "yes", party_size: 1)
    submit(status: "no")
    expect(guest.reload).to be_rsvp_no
    expect(event.activities.recent.first.action).to eq("rsvp_changed")
  end

  it "rejects a party larger than the invitation allows" do
    rsvp = submit(status: "yes", party_size: 4)
    expect(rsvp.errors[:party_size]).to be_present
    expect(guest.reload).to be_rsvp_pending
  end

  it "requires a choice" do
    expect(submit(status: nil).errors[:status]).to be_present
  end

  it "rejects maybe when the host turned it off" do
    event.update!(allow_maybe: false)
    expect(submit(status: "maybe", party_size: 1).errors[:status]).to be_present
  end

  describe "capacity" do
    before { event.update!(capacity: 4) }

    it "rejects a yes that would exceed capacity" do
      create(:guest, event: event, rsvp_status: "yes", party_size: 3)
      rsvp = submit(status: "yes", party_size: 2)
      expect(rsvp.errors[:party_size].join).to include("Only 1 spot left")
      expect(guest.reload).to be_rsvp_pending
    end

    it "doesn't count the guest's own earlier yes against them" do
      submit(status: "yes", party_size: 3)
      rsvp = submit(status: "yes", party_size: 3)
      expect(rsvp.errors).to be_empty
    end

    it "always allows declining a full event" do
      create(:guest, event: event, rsvp_status: "yes", party_size: 4)
      expect(submit(status: "no").errors).to be_empty
    end

    it "lets a host override capacity" do
      create(:guest, event: event, rsvp_status: "yes", party_size: 4)
      rsvp = submit(status: "yes", party_size: 2, by_host: true)
      expect(rsvp.errors).to be_empty
      expect(event.attending_count).to eq(6)
    end
  end

  describe "deadlines and event state" do
    it "rejects guest responses after the deadline but allows the host" do
      event.update!(rsvp_deadline: 1.day.from_now)
      travel_to(2.days.from_now) do
        expect(submit(status: "yes", party_size: 1).errors[:base].join).to include("deadline has passed")
        expect(submit(status: "yes", party_size: 1, by_host: true).errors).to be_empty
      end
    end

    it "rejects responses for cancelled or unpublished events" do
      draft_guest = create(:guest, event: create(:event))
      expect(submit(on: draft_guest, status: "yes", party_size: 1).errors[:base]).to be_present

      event.cancel
      expect(submit(status: "yes", party_size: 1).errors[:base].join).to include("cancelled")
    end
  end

  describe "custom questions" do
    let!(:meal) { create(:event_question, event: event, prompt: "Meal?", options: %w[Fish Veg], required: true) }
    let!(:song) { create(:event_question, event: event, prompt: "Song request?", kind: "short_text", applies_to: "all") }

    it "saves answers" do
      submit(status: "yes", party_size: 1, answers: { meal.id.to_s => "Veg", song.id.to_s => "September" })
      expect(guest.rsvp_answers.pluck(:value)).to contain_exactly("Veg", "September")
    end

    it "requires required questions that apply to the response" do
      rsvp = submit(status: "yes", party_size: 1, answers: {})
      expect(rsvp.errors[:base]).to include("Please answer: Meal?")
    end

    it "doesn't require attending-only questions when declining, and drops stale answers" do
      submit(status: "yes", party_size: 1, answers: { meal.id.to_s => "Fish" })
      rsvp = submit(status: "no", answers: { song.id.to_s => "Dancing Queen" })
      expect(rsvp.errors).to be_empty
      expect(guest.rsvp_answers.map(&:event_question)).to eq([ song ])
    end

    it "only accepts listed choices" do
      rsvp = submit(status: "yes", party_size: 1, answers: { meal.id.to_s => "Steak" })
      expect(rsvp.errors[:base].join).to include("pick one of the listed answers")
    end
  end
end
