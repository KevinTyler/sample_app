module AuthenticationHelpers
  def sign_in(user, password: "correct-horse-battery")
    post session_path, params: { email_address: user.email_address, password: password }
    expect(response).to redirect_to(root_url).or redirect_to(events_url)
  end
end
