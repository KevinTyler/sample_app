require "rails_helper"

RSpec.describe "Multi-part events", type: :request do
  let(:host) { create(:user) }
  let(:event) { create(:event, :published, owner: host, title: "Priya & Theo", time_zone: "Asia/Kolkata") }
  let!(:family) { create(:guest, event: event, name: "Aunt Meera", group_name: "Family", plus_ones_allowed: 1) }
  let!(:friend) { create(:guest, event: event, name: "Lee Park", group_name: "Friends") }

  before do
    sign_in host
    post event_schedule_items_path(event), params: { schedule_item: { name: "Mehndi", starts_at_local: "2027-01-14T16:00", audience_groups: [ "Family" ], collects_replies: "1" } }
    post event_schedule_items_path(event), params: { schedule_item: { name: "Reception", starts_at_local: "2027-01-16T19:30", location_name: "The Leela", collects_replies: "1" } }
    delete session_path
  end

  let(:mehndi) { event.schedule_items.find_by!(name: "Mehndi") }
  let(:reception) { event.schedule_items.find_by!(name: "Reception") }

  it "shows each guest only the parts they're invited to, in the event's time zone" do
    get guest_invitation_path(family.access_token)
    schedule = Nokogiri::HTML(response.body).at_css("[aria-labelledby=schedule-heading]").text.squish
    expect(schedule).to include("Mehndi", "4 PM", "Reception", "7:30 PM", "The Leela")

    get guest_invitation_path(friend.access_token)
    schedule = Nokogiri::HTML(response.body).at_css("[aria-labelledby=schedule-heading]").text.squish
    expect(schedule).to include("Reception")
    expect(schedule).not_to include("Mehndi")
  end

  it "records which parts each guest will attend and counts heads per part" do
    patch guest_rsvp_path(family.access_token), params: { rsvp: { status: "yes", party_size: "2",
      schedule: { mehndi.id.to_s => "1", reception.id.to_s => "0" } } }
    patch guest_rsvp_path(friend.access_token), params: { rsvp: { status: "yes", party_size: "1", schedule: { reception.id.to_s => "1" } } }

    expect(mehndi.headcount).to eq(2)
    expect(reception.headcount).to eq(1)
    expect(family.schedule_replies.find_by(schedule_item: reception).attending).to be(false)

    sign_in host
    get event_path(event)
    tally = Nokogiri::HTML(response.body).css(".tally li").map { |li| li.css("span, strong").first(2).map(&:text).join(" ") }
    expect(tally).to include("Mehndi 2", "Reception 1")
    get export_event_guests_path(event, format: :csv)
    expect(response.body).to include("Attending: Mehndi", "Attending: Reception")
  end

  it "needs at least one part when someone says yes" do
    patch guest_rsvp_path(friend.access_token), params: { rsvp: { status: "yes", party_size: "1", schedule: { reception.id.to_s => "0" } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page_text).to include("Choose at least one of the events")
  end

  it "validates times and keeps the schedule private to editors" do
    sign_in host
    post event_schedule_items_path(event), params: { schedule_item: { name: "Brunch", starts_at_local: "2027-01-17T11:00", ends_at_local: "2027-01-17T10:00" } }
    expect(response).to have_http_status(:unprocessable_content)

    staff = create(:user)
    event.memberships.create!(user: staff, role: "checkin")
    delete session_path
    sign_in staff
    get event_schedule_items_path(event)
    expect(response).to redirect_to(event_path(event))
  end
end
