require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SampleApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # mail_delivery/ is required explicitly by config/initializers/mail_delivery.rb.
    config.autoload_lib(ignore: %w[assets tasks mail_delivery])

    # Stored times are UTC; each event carries its own IANA time zone for display.
    config.time_zone = "UTC"

    # The local outbox (/dev/outbox) captures email and SMS instead of sending them.
    config.x.outbox_enabled = false

    config.generators do |g|
      g.system_tests = nil
      g.test_framework :rspec
      g.helper false
    end
  end
end
