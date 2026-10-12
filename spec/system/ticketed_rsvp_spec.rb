require "rails_helper"

RSpec.describe "Paying for a ticketed event in a browser", type: :system, js: true do
  it "RSVPs, checks out and shows the guest as paid" do
    event = create(:event, :published, ticket_price: "15")
    guest = create(:guest, event: event, name: "Robin Lake", plus_ones_allowed: 1)

    visit guest_invitation_path(guest.access_token)
    find("label.rsvp-choice", text: "Joyfully accepts").click
    select "2", from: "How many in your party (including you)?"
    click_button "Send my RSVP"
    expect(page).to have_content("complete your payment")

    click_button "Pay $30 USD"                 # a native (non-Turbo) form POST from the guest page
    expect(page).to have_content(/test checkout/i)
    click_button "Pay $30 USD"
    expect(page).to have_content("Payment received")
    expect(page).to have_content("$30 USD for 2 tickets")
    expect(guest.reload.amount_due_cents).to eq(0)
  end
end
