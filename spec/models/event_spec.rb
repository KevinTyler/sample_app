require "rails_helper"

RSpec.describe Event do
  describe "local time fields" do
    it "interprets form times in the event's own time zone and stores UTC" do
      event = build(:event, time_zone: "America/Chicago", starts_at: nil)
      event.starts_at_local = "2030-11-07T19:00"
      expect(event).to be_valid
      expect(event.starts_at.utc).to eq(Time.utc(2030, 11, 8, 1, 0))
      expect(event.starts_at_local).to eq("2030-11-07T19:00")
    end

    it "uses the time zone submitted alongside the times" do
      event = build(:event, starts_at: nil)
      event.assign_attributes(starts_at_local: "2030-07-01T12:00", time_zone: "Asia/Tokyo")
      event.validate
      expect(event.starts_at.utc).to eq(Time.utc(2030, 7, 1, 3, 0))
    end

    it "reports unparseable times instead of silently dropping them" do
      event = build(:event, starts_at_local: "next tuesday")
      expect(event).not_to be_valid
      expect(event.errors[:starts_at]).to include("is not a valid date and time")
    end

    it "clears a time when the field is blanked" do
      event = create(:event, ends_at: 4.weeks.from_now)
      event.update!(ends_at_local: "")
      expect(event.ends_at).to be_nil
    end
  end

  describe "validations" do
    it "rejects unknown time zones" do
      expect(build(:event, time_zone: "Mars/Olympus")).not_to be_valid
    end

    it "requires the end to be after the start" do
      event = build(:event, starts_at: 2.weeks.from_now, ends_at: 1.week.from_now)
      expect(event).not_to be_valid
      expect(event.errors[:ends_at]).to be_present
    end

    it "requires the RSVP deadline to fall before the event ends" do
      event = build(:event, starts_at: 2.weeks.from_now, rsvp_deadline: 3.weeks.from_now)
      expect(event).not_to be_valid
      expect(event.errors[:rsvp_deadline]).to be_present
    end

    it "only accepts http(s) video links" do
      expect(build(:event, video_url: "javascript:alert(1)")).not_to be_valid
      expect(build(:event, video_url: "https://meet.example.com/abc")).to be_valid
    end

    it "requires a positive capacity when set" do
      expect(build(:event, capacity: 0)).not_to be_valid
      expect(build(:event, capacity: nil)).to be_valid
    end
  end

  describe "#publish" do
    it "publishes a draft with a future start" do
      event = create(:event)
      expect(event.publish).to be(true)
      expect(event.reload).to be_published
      expect(event.published_at).to be_present
    end

    it "refuses to publish without a start time" do
      event = create(:event, starts_at: nil)
      expect(event.publish).to be(false)
      expect(event.reload).to be_draft
      expect(event.errors[:starts_at]).to be_present
    end

    it "refuses to publish an event that already started" do
      event = create(:event)
      event.update_column(:starts_at, 1.hour.ago)
      expect(event.publish).to be(false)
      expect(event.reload).to be_draft
    end
  end

  describe "#cancel" do
    it "cancels and bumps the calendar sequence so calendars update" do
      event = create(:event, :published)
      expect { event.cancel(note: "Venue flooded") }.to change { event.calendar_sequence }.by(1)
      expect(event).to be_cancelled
      expect(event.cancellation_note).to eq("Venue flooded")
      expect(event.accepting_rsvps?).to be(false)
    end

    it "is a no-op for an already-cancelled event" do
      event = create(:event, :cancelled)
      expect(event.cancel).to be(false)
    end
  end

  describe "#duplicate" do
    let(:event) { create(:event, :published, design: { "template" => "starlit" }) }

    before do
      create(:event_question, event: event)
      create(:guest, event: event, rsvp_status: "yes", party_size: 2, responded_at: Time.current, invited_at: Time.current)
    end

    it "copies details, design and questions into a new draft without guests by default" do
      copy = event.duplicate
      expect(copy).to be_persisted.and be_draft
      expect(copy.title).to eq("Copy of Maya's Birthday")
      expect(copy.design["template"]).to eq("starlit")
      expect(copy.questions.count).to eq(1)
      expect(copy.guests).to be_empty
      expect(copy.share_token).not_to eq(event.share_token)
    end

    it "optionally copies guests with fresh links and no RSVP history" do
      copy = event.duplicate(include_guests: true)
      guest = copy.guests.sole
      original = event.guests.sole
      expect(guest.name).to eq(original.name)
      expect(guest.token_key).not_to eq(original.token_key)
      expect(guest).to be_rsvp_pending
      expect(guest.invited_at).to be_nil
    end
  end

  describe "#accepting_rsvps?" do
    it "closes at the RSVP deadline" do
      event = create(:event, :published, rsvp_deadline: 1.week.from_now)
      expect(event.accepting_rsvps?).to be(true)
      travel_to(8.days.from_now) { expect(event.accepting_rsvps?).to be(false) }
    end

    it "is closed for drafts and cancelled events" do
      expect(create(:event).accepting_rsvps?).to be(false)
      expect(create(:event, :cancelled).accepting_rsvps?).to be(false)
    end
  end

  describe "#rsvp_summary" do
    it "counts responses and headcount" do
      event = create(:event, :published, capacity: 10)
      create(:guest, event: event, rsvp_status: "yes", party_size: 3)
      create(:guest, event: event, rsvp_status: "maybe", party_size: 2)
      create(:guest, event: event, rsvp_status: "no")
      create(:guest, event: event)

      summary = event.rsvp_summary
      expect(summary).to include(invited: 4, yes: 1, maybe: 1, no: 1, pending: 1, attending: 3, maybe_headcount: 2)
      expect(event.spots_remaining).to eq(7)
    end
  end
end
