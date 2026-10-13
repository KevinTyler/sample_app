require "rails_helper"

RSpec.describe "Talking to the agent in the browser", type: :system, js: true do
  let(:host) { create(:user, name: "Jordan Reyes") }

  it "sends with Enter, shows the reply when it arrives, and takes a dropped-in guest list" do
    sign_in_as host
    perform_enqueued_jobs do
      find("textarea[name='body']").send_keys("Plan something new", :enter)
      expect(page).to have_content("What are we celebrating?", wait: 8)
      expect(page).to have_no_css("#agent-thinking")
      expect(find("textarea[name='body']").value).to eq("")

      csv = Rails.root.join("tmp", "maya-30th-guest-list.csv")
      File.write(csv, "Name,Email,Status\nDana Whitfield,dana@example.com,Attending\nLee Park,lee@example.com,No reply\n")
      attach_file "file", csv.to_s, make_visible: true
      expect(page).to have_content("Guest list with replies: 2 people", wait: 8)
      click_button "Recreate the event with replies"
      expect(page).to have_content("Brought in 2 people", wait: 8)
    end
    event = host.owned_events.find_by!(title: "Maya 30th")
    expect(event.guests.find_by!(email: "dana@example.com").rsvp_status).to eq("yes")
  end
end
