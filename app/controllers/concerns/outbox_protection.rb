# The capture outbox and the phone simulator exist for development and test-mode deploys. Outside
# development/test they need ENABLE_OUTBOX=1 *and* HTTP basic auth with OUTBOX_PASSWORD: the
# outbox shows every guest's private link, and the simulator can text the agent as any number.
module OutboxProtection
  extend ActiveSupport::Concern

  included do
    before_action :protect_outside_local_environments
  end

  private
    def protect_outside_local_environments
      return if Rails.env.local?

      password = ENV["OUTBOX_PASSWORD"].to_s
      return head(:forbidden) if password.length < 12

      http_basic_authenticate_or_request_with(name: "outbox", password: password, realm: "Outbox")
    end
end
