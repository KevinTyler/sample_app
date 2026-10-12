# Twilio callbacks, verified with X-Twilio-Signature (HMAC-SHA1 of the URL and POST params, keyed
# by TWILIO_AUTH_TOKEN). Point the number's "A message comes in" webhook at /webhooks/twilio/inbound;
# the status callback is set per message by Messaging::Sms::TwilioAdapter.
class Webhooks::TwilioController < Webhooks::BaseController
  STOP_WORDS = %w[STOP STOPALL UNSUBSCRIBE CANCEL END QUIT].freeze
  STATUS_MAP = { "delivered" => :delivered, "undelivered" => :bounced, "failed" => :failed }.freeze

  before_action :verify_signature

  def self.signature(token, url, post_params)
    data = url + post_params.sort.map { |key, value| "#{key}#{value}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", token, data))
  end

  def status
    delivery = Delivery.find_by(channel: "sms", provider_message_id: params[:MessageSid].to_s)
    event = STATUS_MAP[params[:MessageStatus].to_s]
    delivery.record_provider_event!(event, reason: params[:ErrorCode].presence && "Twilio error #{params[:ErrorCode]}") if delivery && event
    head :no_content
  end

  # Honors STOP replies: stops all messages to that number (Twilio also blocks further sends itself).
  def inbound
    if params[:Body].to_s.strip.upcase.in?(STOP_WORDS)
      phone = PhoneNumber.normalize(params[:From])
      Guest.where(phone: phone, unsubscribed_at: nil).update_all(unsubscribed_at: Time.current) if phone
    end
    render xml: "<Response/>"
  end

  private
    def verify_signature
      token = ENV["TWILIO_AUTH_TOKEN"].to_s
      return head(:not_found) if token.blank?

      expected = self.class.signature(token, request.original_url, request.POST)
      head :forbidden unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Twilio-Signature"].to_s)
    end
end
