module SystemHelpers
  def sign_in_as(user, password: "correct-horse-battery")
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: password
    click_button "Sign in"
    expect(page).to have_content("What can I take off")
  end

  def css_var(selector, name)
    page.evaluate_script("getComputedStyle(document.querySelector('#{selector}')).getPropertyValue('#{name}').trim()")
  end
end

RSpec.configure { |config| config.include SystemHelpers, type: :system }
