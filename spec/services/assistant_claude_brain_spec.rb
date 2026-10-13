require "rails_helper"

RSpec.describe Assistant::ClaudeBrain do
  let(:user) { create(:user, name: "Maria Lopez") }
  let(:conversation) { AssistantConversation.create!(channel: "sms", address: "+15550177", user: user) }
  let(:client) { Anthropic::Client.new(api_key: "test-key", max_retries: 0) }
  let(:api) { %r{\Ahttps://api\.anthropic\.com/v1/messages} }

  def api_message(content, stop_reason)
    { id: "msg_#{SecureRandom.hex(4)}", type: "message", role: "assistant", model: "claude-opus-5-5", content: content,
      stop_reason: stop_reason, stop_sequence: nil, usage: { input_tokens: 10, output_tokens: 10 } }.to_json
  end

  it "runs the tools Claude asks for and texts back its final answer" do
    requests = []
    stub_request(:post, api).to_return(
      lambda { |request|
        requests << JSON.parse(request.body)
        { status: 200, headers: { "Content-Type" => "application/json" }, body: api_message(
          [ { type: "tool_use", id: "toolu_1", name: "create_event",
              input: { title: "Jonah's 5th Birthday", starts_at: "2026-11-14T14:00", location_name: "Lakeside Park", track_kids: true } } ],
          "tool_use") }
      },
      lambda { |request|
        requests << JSON.parse(request.body)
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: api_message([ { type: "text", text: "Done! Jonah's 5th is set for Sat Nov 14 at 2 PM. Pick a look: 1 Balloon Bunch, 2 Confetti Burst." } ], "end_turn") }
      }
    )
    inbound = conversation.messages.create!(direction: "in", body: "Jonah's 5th birthday party, Sat Nov 14 at 2pm, Lakeside Park")

    reply = described_class.new(conversation, inbound, client: client).reply

    expect(reply).to start_with("Done! Jonah's 5th is set")
    event = conversation.reload.event
    expect(event).to have_attributes(title: "Jonah's 5th Birthday", location_name: "Lakeside Park", track_kids: true, owner: user)
    expect(event.local(event.starts_at).strftime("%Y-%m-%d %H:%M")).to eq("2026-11-14 14:00")

    first = requests.first
    expect(first["model"]).to eq("claude-opus-5-5")
    expect(first["fallbacks"]).to eq("default")
    expect(first["output_config"]).to eq("effort" => "medium")
    expect(first["system"].first).to include("cache_control" => { "type" => "ephemeral" })
    expect(first["tools"].map { |t| t["name"] }).to include("create_event", "set_design", "add_guests", "send_invitations", "save_thank_you")
    expect(first["tools"].find { |t| t["name"] == "add_guests" }.dig("input_schema", "properties", "guests", "type")).to eq("array")
    expect(first["messages"].last["content"].first["text"]).to include("Context from Cordially", "Account: Maria Lopez")
    expect(first["messages"].last["content"].last["text"]).to include("Lakeside Park")
    expect(a_request(:post, api).with(headers: { "anthropic-beta" => /server-side-fallback-2026-07-01/ })).to have_been_made.twice

    second = requests.last
    tool_result = second["messages"].last["content"].first
    expect(tool_result).to include("type" => "tool_result", "tool_use_id" => "toolu_1")
    expect(tool_result["content"].to_s).to include("Created a draft")
  end

  it "turns tool errors into something Claude can read and refuses to send without the host's go-ahead" do
    event = create(:event, owner: user)
    conversation.update!(event: event)
    create(:guest, event: event, phone: "+15550100")
    inbound = conversation.messages.create!(direction: "in", body: "looks good")
    results = []
    stub_request(:post, api).to_return(
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: api_message([ { type: "tool_use", id: "toolu_9", name: "send_invitations", input: {} } ], "tool_use") },
      lambda { |request|
        results << JSON.parse(request.body)["messages"].last["content"].first
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: api_message([ { type: "text", text: "Reply SEND and I'll send it to 1 guest." } ], "end_turn") }
      }
    )

    expect(described_class.new(conversation, inbound, client: client).reply).to include("Reply SEND")
    expect(results.first).to include("is_error" => true)
    expect(results.first["content"].to_s).to include("Not confirmed")
    expect(event.messages).to be_empty
  end

  it "answers a refusal politely" do
    stub_request(:post, api).to_return(status: 200, headers: { "Content-Type" => "application/json" },
      body: api_message([], "refusal"))
    inbound = conversation.messages.create!(direction: "in", body: "something off-topic")
    expect(described_class.new(conversation, inbound, client: client).reply).to eq(described_class::REFUSAL_REPLY)
  end
end
