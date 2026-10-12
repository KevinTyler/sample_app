require "rails_helper"

RSpec.describe "Security headers", type: :request do
  def nonce = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]

  it "sends a strict CSP whose nonce is unpredictable on a first visit and stable across a session" do
    get root_path
    first = nonce
    expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'", "object-src 'none'", "frame-ancestors 'none'")
    expect(first).to be_present

    get about_path
    expect(nonce).to eq(first) # Turbo Drive keeps the first page's CSP, so the nonce must not change

    reset!
    get root_path
    expect(nonce).not_to eq(first) # a different visitor gets a different nonce
  end
end
