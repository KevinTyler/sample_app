module MailDelivery
  # ActionMailer delivery method that stores mail in the OutboxItem table (viewable at /dev/outbox)
  # instead of sending it. Used in development and for demos without SMTP credentials.
  class Outbox
    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      OutboxItem.create!(
        channel: "email",
        recipient: Array(mail.to).join(", "),
        subject: mail.subject,
        text_body: (mail.text_part || (mail.multipart? ? nil : mail))&.decoded,
        html_body: mail.html_part&.decoded,
        metadata: { "message_id" => mail.message_id, "attachments" => mail.attachments.map(&:filename) }
      )
    end
  end

  # Used in production when no SMTP server is configured: fails loudly (the delivery is marked
  # failed with a clear reason in the dashboard) rather than silently dropping guest email.
  class Unconfigured
    def initialize(settings = {}); end

    def deliver!(_mail)
      raise Messaging::NotConfigured, "Email is not configured (set SMTP_ADDRESS; see README)"
    end
  end
end
