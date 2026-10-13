module Messaging
  module Whatsapp
    # WhatsApp through Twilio. Enable with WHATSAPP_PROVIDER=twilio and WHATSAPP_FROM_NUMBER=+1555…
    # (a WhatsApp-enabled Twilio sender), plus the TWILIO_* credentials.
    #
    # WhatsApp only allows free-form messages inside a 24-hour window after the person last wrote to
    # you (always true for the texting assistant). Messages you start — guest invitations and reminders —
    # must use a template Meta has approved: create one in Twilio's Content Template Builder with two
    # variables ({{1}} = the message, {{2}} = the link) and set WHATSAPP_TEMPLATE_SID to its HX… id.
    module TwilioAdapter
      module_function

      def configured?
        TwilioApi.configured? && from_number.present?
      end

      def deliver(delivery)
        composer = SmsComposer.new(delivery)
        if template_sid.present?
          variables = { "1" => composer.headline_text, "2" => delivery.personal_url }
          send_message(to: delivery.recipient, extra: [ [ "ContentSid", template_sid ], [ "ContentVariables", variables.to_json ] ])
        else
          send_text(to: delivery.recipient, body: composer.body)
        end
      end

      def send_text(to:, body:, media_urls: [], metadata: {})
        send_message(to: to, extra: [ [ "Body", body ], *media_urls.first(1).map { |url| [ "MediaUrl", url ] } ])
      end

      def send_message(to:, extra:)
        raise Delivery::PermanentError, "Phone number must start with + and a country code" unless to.to_s.start_with?("+")

        TwilioApi.create_message([ [ "To", "whatsapp:#{to}" ], [ "From", "whatsapp:#{from_number}" ], *extra ])
      end

      def from_number = ENV["WHATSAPP_FROM_NUMBER"]
      def template_sid = ENV["WHATSAPP_TEMPLATE_SID"]
    end
  end
end
