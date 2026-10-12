require "rails_helper"

RSpec.describe CalendarInvite do
  let(:event) do
    create(:event, :published, title: "Dinner; drinks, and more", time_zone: "America/Los_Angeles",
      starts_at: Time.utc(2030, 5, 2, 2, 0), description: "Line one\nLine two with a very long sentence that keeps going and going so that the folding logic has to kick in properly.")
  end

  it "builds a valid iCalendar file with escaped text, UTC times and folded lines" do
    ics = described_class.new(event, url: "https://example.com/i/abc").to_ics
    expect(ics).to include("BEGIN:VCALENDAR\r\n", "DTSTART:20300502T020000Z", "DTEND:20300502T050000Z")
    expect(ics).to include('SUMMARY:Dinner\; drinks\, and more')
    expect(ics).to include('Line one\\nLine two')
    expect(ics.split("\r\n")).to all(satisfy { |line| line.bytesize <= 75 })
    expect(ics).to end_with("END:VCALENDAR\r\n")
  end

  it "marks cancelled events so calendar apps remove them" do
    event.cancel
    ics = described_class.new(event).to_ics
    expect(ics).to include("STATUS:CANCELLED", "SEQUENCE:1", "SUMMARY:CANCELLED: Dinner")
  end

  it "builds Google and Outlook links" do
    invite = described_class.new(event)
    expect(invite.google_url).to start_with("https://calendar.google.com/calendar/render?")
    expect(invite.google_url).to include("dates=20300502T020000Z%2F20300502T050000Z")
    expect(invite.outlook_url).to include("startdt=2030-05-02T02%3A00%3A00Z")
  end
end
