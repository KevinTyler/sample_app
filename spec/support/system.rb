require "capybara/cuprite"

# JavaScript system specs run in headless Chrome via Cuprite (Chrome DevTools Protocol, no
# chromedriver). Set BROWSER_PATH to point at Chrome/Chromium if it isn't on the default path.
# When no browser is available the specs are skipped rather than failing.
CHROME_PATH = ENV["BROWSER_PATH"].presence ||
  [ "/opt/pw-browsers/chromium", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/google-chrome" ].find { |p| File.executable?(p) }

Capybara.register_driver(:larkspur_cuprite) do |app|
  options = { window_size: [ 1280, 900 ], headless: true, process_timeout: 20, timeout: 10,
              browser_options: { "no-sandbox" => nil } }
  options[:browser_path] = CHROME_PATH if CHROME_PATH
  Capybara::Cuprite::Driver.new(app, **options)
end

Capybara.default_max_wait_time = 4
Capybara.server = :puma, { Silent: true }

RSpec.configure do |config|
  config.before(:each, type: :system) do |example|
    if example.metadata[:js]
      skip "No Chrome/Chromium found (set BROWSER_PATH)" unless CHROME_PATH || system("which chrome > /dev/null 2>&1")
      driven_by :larkspur_cuprite
    else
      driven_by :rack_test
    end
  end
end
