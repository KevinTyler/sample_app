require "rails_helper"

# On a deployed test server (ENABLE_OUTBOX=1) the outbox and the phone simulator are behind a password:
# the outbox shows guests' private links and the simulator can text the agent as any number.
RSpec.describe "Outbox and phone simulator on a deployed server", type: :request do
  before { allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production")) }

  around do |example|
    ENV["OUTBOX_PASSWORD"] = "a-long-outbox-password"
    example.run
  ensure
    ENV.delete("OUTBOX_PASSWORD")
  end

  let(:auth) { { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("outbox", "a-long-outbox-password") } }

  it "asks for the password before showing either" do
    get dev_outbox_index_path
    expect(response).to have_http_status(:unauthorized)
    get dev_assistant_path
    expect(response).to have_http_status(:unauthorized)
    post dev_assistant_path, params: { phone: "+15550177777", body: "LINK ABC123" }
    expect(response).to have_http_status(:unauthorized)
    expect(AssistantConversation.count).to eq(0)

    get dev_assistant_path, headers: auth
    expect(response).to have_http_status(:ok)
  end

  it "stays closed when no proper password is set" do
    ENV["OUTBOX_PASSWORD"] = "short"
    get dev_assistant_path, headers: auth
    expect(response).to have_http_status(:forbidden)
  end
end
