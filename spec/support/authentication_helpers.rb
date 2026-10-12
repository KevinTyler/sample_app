module AuthenticationHelpers
  def sign_in(user, password: "correct-horse-battery")
    post session_path, params: { email_address: user.email_address, password: password }
    expect(response).to be_redirect
    expect(response.location).not_to include("/session/new")
  end
end
