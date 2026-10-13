# Sends a thank-you link by text or email. Each thank-you is sent at most once by Cordially
# (an atomic claim on sent_at); a failed send releases the claim so the host can retry.
class ThankYouSender
  CHANNELS = %w[sms email].freeze

  class Unavailable < StandardError; end

  def self.channel_for(thank_you)
    if thank_you.recipient_phone.present? && Messaging.sms_enabled? then "sms"
    elsif thank_you.recipient_email.present? then "email"
    end
  end

  def initialize(thank_you, channel: self.class.channel_for(thank_you))
    @thank_you = thank_you
    @channel = channel
  end

  def deliver!
    raise Unavailable, "#{@thank_you.recipient_name} has no #{@channel == 'sms' ? 'mobile number' : 'email address'}" unless reachable?
    raise Unavailable, "Add a photo, video or note first" unless @thank_you.ready?
    return false unless claim!

    begin
      url = Rails.application.routes.url_helpers.thank_you_page_url(@thank_you.token, **Messaging.url_options)
      if @channel == "sms"
        Messaging.sms_gateway.send_text(to: @thank_you.recipient_phone, body: @thank_you.share_text(url), metadata: { thank_you_id: @thank_you.id })
      else
        ThankYouMailer.with(thank_you: @thank_you, url: url).note.deliver_now
      end
    rescue StandardError
      ThankYou.where(id: @thank_you.id).update_all(sent_at: nil, sent_via: nil)
      raise
    end
    Activity.record(event: @thank_you.event, guest: @thank_you.guest, action: "thank_you_sent", data: { name: @thank_you.recipient_name, via: @channel })
    true
  end

  private
    def reachable?
      case @channel
      when "sms" then @thank_you.recipient_phone.present? && Messaging.sms_enabled?
      when "email" then @thank_you.recipient_email.present?
      else false
      end
    end

    def claim!
      ThankYou.where(id: @thank_you.id, sent_at: nil).update_all(sent_at: Time.current, sent_via: @channel, updated_at: Time.current) == 1
    end
end
