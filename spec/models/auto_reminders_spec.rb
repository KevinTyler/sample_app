require "rails_helper"

RSpec.describe AutoReminders do
  let(:deadline) { 10.days.from_now.change(hour: 12) }
  let(:event) do
    create(:event, :published, starts_at: 14.days.from_now.change(hour: 23), rsvp_deadline: deadline,
      auto_nudge: true, nudge_days_before: 3, auto_day_before: true)
  end

  def reminder(key) = event.messages.find_by(idempotency_key: key)

  it "schedules a nudge for non-responders and a day-before note at 10am event time" do
    nudge = reminder(AutoReminders::NUDGE_KEY)
    expect(nudge).to have_attributes(kind: "reminder", status: "scheduled")
    expect(nudge.scheduled_for).to eq(event.local(deadline - 3.days).change(hour: 10))
    expect(nudge.audience.statuses).to eq([ "pending" ])

    day_before = reminder(AutoReminders::DAY_BEFORE_KEY)
    expect(day_before.scheduled_for).to eq(event.local(event.starts_at - 1.day).change(hour: 10))
    expect(day_before.audience.statuses).to eq(%w[yes maybe])
  end

  it "moves reminders when dates change and withdraws them when turned off or cancelled" do
    event.update!(rsvp_deadline: deadline + 2.days)
    expect(reminder(AutoReminders::NUDGE_KEY).scheduled_for).to eq(event.local(deadline - 1.day).change(hour: 10))

    event.update!(auto_nudge: false)
    expect(reminder(AutoReminders::NUDGE_KEY)).to be_nil

    event.cancel
    expect(reminder(AutoReminders::DAY_BEFORE_KEY)).to be_nil
  end

  it "does nothing for drafts and never touches a reminder that already went out" do
    draft = create(:event, starts_at: 5.days.from_now, auto_day_before: true)
    expect(draft.messages).to be_empty

    reminder(AutoReminders::NUDGE_KEY).update_columns(status: "dispatched")
    event.update!(rsvp_deadline: deadline + 1.day)
    expect(reminder(AutoReminders::NUDGE_KEY).status).to eq("dispatched")
  end
end

RSpec.describe "Cancelling an automatic reminder", type: :request do
  let(:event) { create(:event, :published, starts_at: 14.days.from_now, auto_day_before: true) }

  def reminder(key) = event.messages.find_by(idempotency_key: key)

  it "stays off once the host cancels an automatic reminder" do
    sign_in event.owner
    delete event_message_path(event, reminder(AutoReminders::DAY_BEFORE_KEY))
    expect(event.reload.auto_day_before).to be(false)
    event.update!(starts_at: event.starts_at + 1.day)
    expect(reminder(AutoReminders::DAY_BEFORE_KEY)).to be_nil
  end
end
