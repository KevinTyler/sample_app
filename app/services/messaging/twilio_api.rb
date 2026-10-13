require "net/http"

module Messaging
  # Twilio's Messages API, shared by the SMS and WhatsApp adapters.
  #   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_FROM_NUMBER or TWILIO_MESSAGING_SERVICE_SID.
  module TwilioApi
    API_BASE = "https://api.twilio.com/2010-04-01".freeze

    module_function

    def configured?
      account_sid.present? && auth_token.present?
    end

    # params: array of [name, value] pairs (MediaUrl may repeat). Returns a Receipt.
    def create_message(params)
      raise NotConfigured, "Twilio credentials are missing" unless configured?

      uri = URI("#{API_BASE}/Accounts/#{account_sid}/Messages.json")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(account_sid, auth_token)
      request.set_form_data(params)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      parsed = JSON.parse(response.body) rescue {}

      case response.code.to_i
      when 200..299 then Receipt.new(provider: "twilio", message_id: parsed["sid"])
      when 400..499 then raise Delivery::PermanentError, "Twilio rejected the message: #{parsed['message'] || response.code}"
      else raise "Twilio error #{response.code}"
      end
    end

    # Downloads media a host texted us (MMS/WhatsApp). Twilio media URLs need the account's credentials.
    def download(url, max_bytes:)
      uri = URI(url)
      raise ArgumentError, "unexpected media host" unless uri.is_a?(URI::HTTPS) && uri.host.end_with?("twilio.com")

      fetch(uri, max_bytes: max_bytes, redirects: 3)
    end

    def fetch(uri, max_bytes:, redirects:)
      request = Net::HTTP::Get.new(uri)
      request.basic_auth(account_sid, auth_token) if uri.host.end_with?("twilio.com")
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) do |http|
        http.request(request) do |response|
          if response.is_a?(Net::HTTPRedirection) && redirects.positive?
            return fetch(URI(response["location"]), max_bytes: max_bytes, redirects: redirects - 1)
          end
          raise "media download failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

          body = +""
          response.read_body do |chunk|
            body << chunk
            raise "media too large" if body.bytesize > max_bytes
          end
          return [ body, response["content-type"].to_s.split(";").first ]
        end
      end
    end

    def account_sid = ENV["TWILIO_ACCOUNT_SID"]
    def auth_token = ENV["TWILIO_AUTH_TOKEN"]
  end
end
