require "rails_helper"

RSpec.describe GuestAccessToken do
  let(:guest) { create(:guest) }

  it "round-trips a guest's personal token" do
    expect(guest.access_token.length).to eq(40)
    expect(Guest.find_by_access_token(guest.access_token)).to eq(guest)
  end

  it "rejects tampered, truncated or malformed tokens" do
    token = guest.access_token
    tampered = token[0..-2] + (token[-1] == "a" ? "b" : "a")

    expect(Guest.find_by_access_token(tampered)).to be_nil
    expect(Guest.find_by_access_token(token[0, 39])).to be_nil
    expect(Guest.find_by_access_token(nil)).to be_nil
    expect(Guest.find_by_access_token("../" + token[3..])).to be_nil
  end

  it "does not accept the stored key alone (the signature needs the app secret)" do
    forged = guest.token_key + ("A" * GuestAccessToken::SIGNATURE_LENGTH)
    expect(Guest.find_by_access_token(forged)).to be_nil
  end

  it "invalidates the old link when the token is rotated" do
    old = guest.access_token
    guest.rotate_access_token!
    expect(Guest.find_by_access_token(old)).to be_nil
    expect(Guest.find_by_access_token(guest.access_token)).to eq(guest)
  end
end
