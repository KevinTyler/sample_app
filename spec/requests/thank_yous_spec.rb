require "rails_helper"

RSpec.describe "Thank-yous", type: :request do
  let(:host) { create(:user, name: "Jordan Rivera") }
  let(:event) { create(:event, :published, owner: host, title: "Jonah's 5th Birthday") }
  let(:dana) { create(:guest, event: event, name: "Dana Whitfield", email: "dana@example.com", phone: "+15550100") }

  def record_video_thank_you
    post event_gifts_path(event), params: { gift: { description: "Dinosaur Lego set", guest_id: dana.id } }
    gift = event.gifts.sole
    post event_thank_yous_path(event), params: { thank_you: { gift_id: gift.id, message: "I built the T. rex already!", signed: "Love, Jonah" },
      media_video: fixture_file_upload("thanks.mp4", "video/mp4") }
    gift.reload.thank_you
  end

  it "logs a gift, records a video thank-you and texts it; the guest opens it and sends a heart" do
    sign_in host
    thank_you = record_video_thank_you
    expect(thank_you).to have_attributes(recipient_name: "Dana Whitfield", recipient_phone: "+15550100", guest: dana)
    expect(thank_you).to be_video
    expect(thank_you).to be_ready

    get event_thank_yous_path(event)
    expect(page_text).to include("Dinosaur Lego set", "from Dana Whitfield", "Recorded · not sent")

    post deliver_event_thank_you_path(event, thank_you, channel: "sms")
    text = OutboxItem.where(channel: "sms").last
    expect(text.recipient).to eq("+15550100")
    expect(text.text_body).to include("Dana, Jonah made you a thank-you for the dinosaur Lego set:", "/t/#{thank_you.token}")
    expect(thank_you.reload).to have_attributes(sent_via: "sms")

    expect { post deliver_event_thank_you_path(event, thank_you, channel: "sms") }.not_to change(OutboxItem, :count)

    delete session_path
    get thank_you_page_path(thank_you.token)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("video.thank-card__media")["src"]).to include("/rails/active_storage/blobs/proxy/")
    expect(doc.at_css(".thank-card").text.squish).to include("I built the T. rex already!", "Love, Jonah", "for the dinosaur Lego set")
    expect(thank_you.reload.viewed_at).to be_present

    post thank_you_page_heart_path(thank_you.token)
    expect(thank_you.reload.hearted_at).to be_present
    expect(event.activities.pluck(:action)).to include("thank_you_sent", "thank_you_viewed", "thank_you_hearted")
  end

  it "emails a written thank-you when there's no phone" do
    lee = create(:guest, event: event, name: "Lee Park", email: "lee@example.com")
    sign_in host
    post event_thank_yous_path(event), params: { thank_you: { guest_id: lee.id, message: "Thanks for coming!", signed: "The Riveras" } }
    thank_you = event.thank_yous.sole
    expect(ThankYouSender.channel_for(thank_you)).to eq("email")

    perform_enqueued_jobs { post deliver_event_thank_you_path(event, thank_you) }
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "lee@example.com" ])
    expect(mail.subject).to eq("A thank-you from The Riveras")
    expect(mail.text_part.body.to_s).to include("Thanks for coming!", thank_you.token)
  end

  it "won't send an empty thank-you, and sends every ready one at once" do
    sign_in host
    empty = event.thank_yous.create!(guest: dana)
    post deliver_event_thank_you_path(event, empty)
    expect(flash[:alert]).to include("Add a photo, video or note first")

    event.thank_yous.create!(guest: create(:guest, event: event, name: "Sam", phone: "+15550199"), message: "Thank you!")
    post deliver_all_event_thank_yous_path(event)
    expect(flash[:notice]).to include("Sent 1 thank-you", "1 not ready")
  end

  it "lets the host mark a thank-you shared from their own phone" do
    sign_in host
    thank_you = event.thank_yous.create!(guest: dana, message: "Thanks!")
    get event_thank_yous_path(event)
    expect(response.body).to include("sms:+15550100?&amp;body=")
    patch mark_sent_event_thank_you_path(event, thank_you)
    expect(thank_you.reload).to have_attributes(sent_via: "shared")
  end

  it "rejects files that aren't photos or videos" do
    sign_in host
    post event_thank_yous_path(event), params: { thank_you: { guest_id: dana.id }, media_library: fixture_file_upload("sneaky.svg", "image/svg+xml") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(event.thank_yous).to be_empty
  end

  it "keeps the gift log and thank-yous from door staff and strangers" do
    staff = create(:user)
    event.memberships.create!(user: staff, role: "checkin")
    sign_in staff
    get event_thank_yous_path(event)
    expect(response).to redirect_to(event_path(event))

    get thank_you_page_path("x" * 40)
    expect(response).to have_http_status(:not_found)
    forged = event.thank_yous.create!(guest: dana, message: "hi").token_key + ("A" * 24)
    get thank_you_page_path(forged)
    expect(response).to have_http_status(:not_found)
  end

  it "doesn't count the host's own look as the guest opening it" do
    sign_in host
    thank_you = event.thank_yous.create!(guest: dana, message: "Thanks!")
    get thank_you_page_path(thank_you.token)
    expect(thank_you.reload.viewed_at).to be_nil
  end
end
