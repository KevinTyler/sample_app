require "rails_helper"

RSpec.describe "Registrations", type: :request do
  it "creates an account and signs the user in" do
    post registration_path, params: { user: { name: "Sam", email_address: "SAM@example.com",
      password: "long-enough-pw", password_confirmation: "long-enough-pw" } }
    expect(response).to redirect_to(agent_path)
    expect(User.last.email_address).to eq("sam@example.com")
  end

  it "rejects short passwords" do
    post registration_path, params: { user: { name: "Sam", email_address: "sam@example.com", password: "short", password_confirmation: "short" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
