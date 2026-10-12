# Delivery feedback from the email provider: delivered / bounced / failed / complained.
#
# Authenticate with `Authorization: Bearer $EMAIL_WEBHOOK_TOKEN` (or ?token=… for providers that can
# only call a URL). Without EMAIL_WEBHOOK_TOKEN set, the endpoint is disabled.
#
# Accepted bodies (a single object or an array):
#   Generic:  { "message_id": "<delivery-12-…@host>", "event": "bounced", "reason": "Mailbox full" }
#   SendGrid: [{ "smtp-id": "<delivery-12-…@host>", "event": "bounce", "reason": "…" }, …]
# Delivery rows are matched on the Message-ID we set on every email.
class Webhooks::EmailController < Webhooks::BaseController
  EVENT_MAP = {
    "delivered" => :delivered, "delivery" => :delivered,
    "bounced" => :bounced, "bounce" => :bounced, "dropped" => :failed, "failed" => :failed,
    "complained" => :complained, "spamreport" => :complained, "spam_complaint" => :complained
  }.freeze

  before_action :authenticate

  def create
    events = Array.wrap(JSON.parse(request.raw_post))
    processed = events.first(1000).count { |payload| apply(payload) if payload.is_a?(Hash) }
    render json: { processed: processed }
  rescue JSON::ParserError
    head :bad_request
  end

  private
    def authenticate
      expected = ENV["EMAIL_WEBHOOK_TOKEN"].to_s
      return head(:not_found) if expected.length < 16

      given = request.authorization.to_s.delete_prefix("Bearer ").presence || params[:token].to_s
      head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(given, expected)
    end

    def apply(payload)
      event = EVENT_MAP[payload["event"].to_s.downcase]
      message_id = (payload["message_id"] || payload["smtp-id"]).to_s.delete("<>").strip
      return false if event.nil? || message_id.blank?

      delivery = Delivery.find_by(channel: "email", provider_message_id: message_id)
      return false unless delivery

      delivery.record_provider_event!(event, reason: payload["reason"] || payload["response"])
      true
    end
end
