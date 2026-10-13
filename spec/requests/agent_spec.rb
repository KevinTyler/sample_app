require "rails_helper"

# The signed-in home is a conversation with the agent. These run the guided brain (no API key in
# tests); the Claude brain shares the same actions (see spec/services/assistant_claude_brain_spec.rb).
RSpec.describe "The agent on the web (Today)", type: :request do
  let(:host) { create(:user, name: "Jordan Reyes") }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def say(body, file: nil)
    perform_enqueued_jobs do
      post agent_messages_path, params: { body: body, file: file }.compact, headers: stream
    end
    expect(response).to have_http_status(:ok)
  end

  def thread = AssistantConversation.find_by!(channel: "web", user: host)
  def last_reply = thread.messages.where(direction: "out").last

  it "is where hosts land after signing in, and needs a session" do
    get agent_path
    expect(response).to redirect_to(new_session_path)

    post session_path, params: { email_address: host.email_address, password: "correct-horse-battery" }
    expect(response).to redirect_to(agent_url)
    follow_redirect!
    expect(page_text).to include("Good", "Jordan", "take off", "Coming over from Paperless Post?", "Bring my Paperless Post guests")
  end

  context "signed in" do
    before { sign_in host }

    it "answers on the page: the message appears, the agent thinks, and the reply arrives by polling" do
      post agent_messages_path, params: { body: "Plan something new" }, headers: stream
      expect(response.body).to include("turbo-stream", "Plan something new", "agent-thinking")
      sent = thread.messages.sole

      perform_enqueued_jobs
      get agent_messages_path(after: sent.id), headers: stream
      expect(response.body).to include("What are we celebrating?")
      expect(response.body).to include('action="remove" target="agent-thinking"')

      say "Jonah's 5th birthday"
      event = host.owned_events.sole
      expect(event).to have_attributes(title: "Jonah's 5th birthday", track_kids: true)
      expect(last_reply.cards).to include("type" => "event", "event_id" => event.id)
      get agent_path
      expect(page_text).to include("Jonah's 5th birthday", "Design", "Guests")
    end

    it "takes a Paperless Post export dropped into the chat and recreates the event with its replies" do
      file = Rack::Test::UploadedFile.new(StringIO.new(xlsx_from([
        [ "Name", "Email", "Status", "# Attending" ],
        [ "Dana Whitfield", "dana@example.com", "Attending", 2 ],
        [ "Lee Park", "lee@example.com", "No reply", nil ]
      ])), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", original_filename: "Maya's 30th - Guest List.xlsx")
      say "", file: file

      import = host.contact_imports.sole
      expect(last_reply.body).to include("Guest list with replies: 2 people", "1 yes", "RECREATE")
      expect(last_reply.cards).to eq([ { "type" => "import", "import_id" => import.id } ])
      get agent_path
      expect(page_text).to include("Maya's 30th - Guest List.xlsx", "Recreate the event with replies", "Just save to contacts")

      post apply_contact_import_path(import), params: { mode: "new_event", from: "agent" }
      expect(response).to redirect_to(agent_path(anchor: "latest"))
      event = host.owned_events.sole
      expect(event).to have_attributes(title: "Maya's 30th", status: "draft")
      expect(event.guests.find_by!(email: "dana@example.com")).to have_attributes(rsvp_status: "yes", party_size: 2)
      expect(last_reply.body).to include("Brought in 2 people", "when is it, and where?")
      expect(thread.reload.event).to eq(event)
    end

    it "brings a pasted list or file in by command too" do
      say "", file: Rack::Test::UploadedFile.new(StringIO.new("Name,Email\nAna Lima,ana@example.com\n"), "text/csv", original_filename: "book-club.csv")
      say "CONTACTS"
      expect(host.contacts.sole).to have_attributes(name: "Ana Lima")
      expect(last_reply.body).to include("Brought in 1 person", "Nobody was contacted")
    end

    it "keeps the conversation's words as text: no HTML, only safe links" do
      thread_record = AssistantConversation.for_web(host)
      thread_record.reply!("<script>alert(1)</script> See /events/1 or https://example.com/x. javascript:alert(2)")
      get agent_path
      expect(response.body).not_to include("<script>alert(1)")
      expect(response.body).to include("&lt;script&gt;", 'href="/events/1"', 'href="https://example.com/x"')
      expect(response.body).not_to include('href="javascript')
    end

    it "connects the host's phone with a one-time code texted to the agent" do
      ENV["ASSISTANT_PHONE_NUMBER"] = "+15550123000"
      post agent_phone_link_path, headers: stream
      code = response.body[/LINK ([A-Z0-9]{6})/, 1]
      expect(code).to be_present
      expect(host.reload.phone_link_code_digest).not_to include(code)

      Assistant::Inbound.receive(channel: "sms", address: "+15550177777", body: "LINK ZZZZZZ", reply_now: true)
      phone = AssistantConversation.find_by!(channel: "sms", address: "+15550177777")
      expect(phone.user).to be_nil
      expect(phone.messages.last.body).to include("didn't work")

      Assistant::Inbound.receive(channel: "sms", address: "+15550177777", body: "link #{code.downcase}", reply_now: true)
      expect(phone.reload.user).to eq(host)
      expect(phone.messages.last.body).to include("Connected, Jordan")
      expect(host.reload).to have_attributes(agent_reach: "text", phone_link_code_digest: nil)

      Assistant::Inbound.receive(channel: "sms", address: "+15550188888", body: "LINK #{code}", reply_now: true)
      expect(AssistantConversation.find_by!(address: "+15550188888").user).to be_nil # single use
      get agent_path
      expect(page_text).to include("Your phone (•••7777) is connected")
    ensure
      ENV.delete("ASSISTANT_PHONE_NUMBER")
    end

    it "stops guessing link codes after a few tries" do
      Assistant::Inbound::MAX_LINK_ATTEMPTS.times { |i| Assistant::Inbound.receive(channel: "sms", address: "+15550199999", body: "LINK AAAAA#{i}", reply_now: true) }
      code = host.issue_phone_link_code!
      Assistant::Inbound.receive(channel: "sms", address: "+15550199999", body: "LINK #{code}", reply_now: true)
      expect(AssistantConversation.find_by!(address: "+15550199999").user).to be_nil
    end
  end
end
