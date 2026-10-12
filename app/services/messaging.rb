# Entry point for outbound guest messaging. Channels are adapters with one method,
# `deliver(delivery) -> Messaging::Receipt`, so providers can be swapped by configuration:
#
#   Email: ActionMailer. Development/test use the local Outbox (see /dev/outbox);
#          production uses SMTP (Postmark, SES, SendGrid, Mailgun, … all speak SMTP).
#   SMS:   SMS_PROVIDER=outbox (development default) or twilio. Disabled when unset in production.
module Messaging
  Receipt = Data.define(:provider, :message_id)

  class NotConfigured < Delivery::PermanentError; end

  module_function

  def gateway_for(channel)
    case channel.to_s
    when "email" then EmailGateway
    when "sms" then sms_gateway || raise(NotConfigured, "SMS is not configured")
    else raise ArgumentError, "Unknown channel #{channel.inspect}"
    end
  end

  def sms_gateway
    case sms_provider
    when "outbox" then Sms::OutboxAdapter
    when "twilio" then Sms::TwilioAdapter
    end
  end

  def sms_provider
    ENV.fetch("SMS_PROVIDER") { Rails.env.production? ? nil : "outbox" }.presence
  end

  def sms_enabled?
    sms_gateway.present? && sms_gateway.configured?
  end

  def url_options
    Rails.application.config.action_mailer.default_url_options || {}
  end

  def outbox_enabled?
    Rails.application.config.x.outbox_enabled
  end
end
