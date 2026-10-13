require "rails_helper"

RSpec.describe "Texting assistant", type: :request do
  around do |example|
    ENV["TWILIO_AUTH_TOKEN"] = "twilio-token"
    example.run
  ensure
    ENV.delete("TWILIO_AUTH_TOKEN")
  end

  def text(body, from: "+15550177", media: [], sid: "SM#{SecureRandom.hex(8)}")
    params = { From: from, Body: body, MessageSid: sid, NumMedia: media.size.to_s }
    media.each_with_index { |(url, type), i| params[:"MediaUrl#{i}"] = url; params[:"MediaContentType#{i}"] = type }
    url = "http://www.example.com#{webhooks_twilio_assistant_path}"
    signature = Webhooks::TwilioController.signature("twilio-token", url, params.stringify_keys)
    perform_enqueued_jobs do
      post webhooks_twilio_assistant_path, params: params, headers: { "X-Twilio-Signature" => signature }
    end
    expect(response).to have_http_status(:ok)
  end

  def last_reply(address = "+15550177", channel: "sms")
    AssistantConversation.find_by!(address: address, channel: channel).messages.where(direction: "out").last.body
  end

  it "sets up an account, a card and a guest list by text, then sends the invitations" do
    text "Hi"
    expect(last_reply).to include("What's your name?")
    text "Maria Lopez"
    text "maria@example.com"
    user = User.find_by!(email_address: "maria@example.com")
    expect(user.name).to eq("Maria Lopez")
    expect(last_reply).to include("What are we celebrating?")

    text "Sofia's 7th birthday"
    text "Sat Nov 14 2pm"
    text "Lakeside Park pavilion"
    expect(last_reply).to include("Pick a look", "2 Balloon Bunch")
    text "2"
    event = user.owned_events.sole
    expect(event).to have_attributes(title: "Sofia's 7th birthday", location_name: "Lakeside Park pavilion", track_kids: true, status: "draft")
    expect(event.design_settings.template).to eq("balloon-bunch")
    expect(last_reply).to match(%r{http://\S+/m/[A-Za-z0-9_-]{32}})

    text "Dana Whitfield 555-010-0100\nLee Park lee@example.com"
    expect(event.guests.pluck(:name, :phone)).to contain_exactly([ "Dana Whitfield", "+15550100100" ], [ "Lee Park", nil ])
    expect(user.contacts.count).to eq(2)

    text "SEND"
    expect(event.reload).to be_published
    expect(last_reply).to include("Sending 2 invitations")
    expect(OutboxItem.where(channel: "sms", recipient: "+15550100100").last.text_body).to include("invited you to Sofia's 7th birthday")
    expect(ActionMailer::Base.deliveries.map(&:to)).to include([ "lee@example.com" ])
  end

  it "texts the host when a guest replies" do
    host = create(:user)
    event = create(:event, :published, owner: host, title: "Sofia's 7th birthday")
    AssistantConversation.create!(channel: "sms", address: "+15550177", user: host, event: event, last_inbound_at: Time.current)
    guest = create(:guest, event: event, name: "Dana Whitfield")
    perform_enqueued_jobs { patch guest_rsvp_path(guest.access_token), params: { rsvp: { status: "yes", party_size: "1" } } }
    expect(last_reply).to eq("Dana Whitfield is coming · Sofia's 7th birthday: 1 coming, 0 still to reply.")
  end

  it "only connects a phone to an existing account after the owner confirms by email" do
    existing = create(:user, name: "Olive Owner", email_address: "olive@example.com")
    text "Hi"
    text "Olive"
    text "olive@example.com"
    conversation = AssistantConversation.find_by!(address: "+15550177")
    expect(conversation.user).to be_nil
    expect(last_reply).to include("emailed olive@example.com a link")

    mail = ActionMailer::Base.deliveries.last
    link = mail.text_part.body.to_s[%r{http://\S+/assistant/connect/\S+}]
    get link
    expect(page_text).to include("Connect this phone")
    expect(conversation.reload.user).to be_nil # just looking doesn't connect it
    post link
    expect(conversation.reload.user).to eq(existing)
    expect(last_reply).to include("Connected to your Cordially account, Olive!")

    post link.sub(/connect\/.{5}/, "connect/xxxxx")
    expect(response).to have_http_status(:not_found)
  end

  it "signs in once with a sign-in link, and not by merely opening it" do
    user = create(:user)
    token = SignInLink.issue!(user, "/events")
    get sign_in_link_path(token)
    expect(response).to have_http_status(:ok)
    expect(SignInLink.last.used_at).to be_nil

    post sign_in_link_path(token)
    expect(response).to redirect_to("/events")
    follow_redirect!
    expect(response).to have_http_status(:ok)

    delete session_path
    post sign_in_link_path(token)
    expect(response).to have_http_status(:not_found)

    expired = SignInLink.issue!(user, "/events")
    travel 31.minutes do
      get sign_in_link_path(expired)
      expect(response).to have_http_status(:not_found)
    end
    expect(SignInLink.new(user: user, redirect_path: "//evil.example", token_digest: "x", expires_at: 1.hour.from_now)).not_to be_valid
  end

  it "makes a thank-you from a video the host texts, then sends it when they say so" do
    host = create(:user)
    event = create(:event, :published, owner: host)
    dana = create(:guest, event: event, name: "Dana Whitfield", phone: "+15550100")
    event.gifts.create!(guest: dana, description: "Dinosaur Lego set")
    AssistantConversation.create!(channel: "sms", address: "+15550177", user: host, event: event)
    video_url = "https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1"
    stub_request(:get, video_url).to_return(status: 200, body: "\x00\x00\x00\x18ftypisom".b, headers: { "Content-Type" => "video/mp4" })
    ENV["TWILIO_ACCOUNT_SID"] = "AC1"

    text "", media: [ [ video_url, "video/mp4" ] ]
    expect(last_reply).to include("Who's it for?")
    text "Dana - Lego"
    thank_you = event.thank_yous.sole
    expect(thank_you).to have_attributes(guest: dana, gift: event.gifts.sole)
    expect(thank_you).to be_video
    expect(last_reply).to include("Reply SEND")

    text "SEND"
    expect(thank_you.reload.sent_via).to eq("sms")
    expect(OutboxItem.where(recipient: "+15550100").last.text_body).to include("/t/#{thank_you.token}")
  ensure
    ENV.delete("TWILIO_ACCOUNT_SID")
  end

  it "works over WhatsApp too, keeps threads per channel, and honors STOP" do
    text "Hi", from: "whatsapp:+15550188"
    expect(last_reply("+15550188", channel: "whatsapp")).to include("What's your name?")
    expect(OutboxItem.where(channel: "whatsapp", recipient: "+15550188")).to exist

    text "STOP", from: "whatsapp:+15550188"
    conversation = AssistantConversation.find_by!(address: "+15550188", channel: "whatsapp")
    expect(conversation).to be_opted_out
    expect { text "hello?", from: "whatsapp:+15550188" }.not_to change { conversation.messages.count }
    text "START", from: "whatsapp:+15550188"
    expect(conversation.reload).not_to be_opted_out
  end

  it "ignores provider retries of the same message and forged requests" do
    text "Hi", sid: "SMsame"
    expect { text "Hi", sid: "SMsame" }.not_to change(AssistantMessage, :count)

    post webhooks_twilio_assistant_path, params: { From: "+15550177", Body: "Hi" }, headers: { "X-Twilio-Signature" => "forged" }
    expect(response).to have_http_status(:forbidden)
  end

  it "has a phone simulator in development" do
    get dev_assistant_path(phone: "+15550199")
    expect(page_text).to include("Text the", "guided mode")
    post dev_assistant_path, params: { phone: "+15550199", body: "Hi" }
    follow_redirect!
    expect(page_text).to include("What's your name?")
  end
end
