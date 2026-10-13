require "net/http"

module Messaging
  module Sms
    # Sends SMS through Twilio's Messages API. Enable with:
    #   SMS_PROVIDER=twilio TWILIO_ACCOUNT_SID=AC… TWILIO_AUTH_TOKEN=… TWILIO_FROM_NUMBER=+1555…
    # (or TWILIO_MESSAGING_SERVICE_SID instead of a from number). Recipients must be in E.164 (+15551234567).
    module TwilioAdapter
      API_BASE = "https://api.twilio.com/2010-04-01".freeze

      module_function

      def configured?
        account_sid.present? && auth_token.present? && (from_number.present? || messaging_service_sid.present?)
      end

      def deliver(delivery)
        send_text(to: delivery.recipient, body: SmsComposer.new(delivery).body, status_callback: status_callback_url)
      end

      # Any one-off text. media_urls (public https URLs) make it an MMS where the carrier supports it.
      def send_text(to:, body:, media_urls: [], metadata: {}, status_callback: nil)
        raise NotConfigured, "Twilio credentials are missing" unless configured?
        raise Delivery::PermanentError, "Phone number must start with + and a country code" unless to.to_s.start_with?("+")

        uri = URI("#{API_BASE}/Accounts/#{account_sid}/Messages.json")
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(account_sid, auth_token)
        params = [ [ "To", to ], [ "Body", body ] ]
        params << (messaging_service_sid.present? ? [ "MessagingServiceSid", messaging_service_sid ] : [ "From", from_number ])
        params << [ "StatusCallback", status_callback ] if status_callback
        media_urls.first(10).each { |url| params << [ "MediaUrl", url ] }
        request.set_form_data(params)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
        parsed = JSON.parse(response.body) rescue {}

        case response.code.to_i
        when 200..299 then Receipt.new(provider: "twilio", message_id: parsed["sid"])
        when 400..499 then raise Delivery::PermanentError, "Twilio rejected the message: #{parsed['message'] || response.code}"
        else raise "Twilio error #{response.code}"
        end
      end

      def status_callback_url
        return unless ENV["APP_HOST"].present?

        Rails.application.routes.url_helpers.webhooks_twilio_status_url(host: ENV["APP_HOST"], protocol: "https")
      end

      def account_sid = ENV["TWILIO_ACCOUNT_SID"]
      def auth_token = ENV["TWILIO_AUTH_TOKEN"]
      def from_number = ENV["TWILIO_FROM_NUMBER"]
      def messaging_service_sid = ENV["TWILIO_MESSAGING_SERVICE_SID"]
    end
  end
end
