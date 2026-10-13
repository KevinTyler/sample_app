module Messaging
  # Builds the short plain-text body for SMS and WhatsApp deliveries, in the event's language.
  class SmsComposer
    MAX_LENGTH = 480 # ~3 SMS segments

    def initialize(delivery)
      @delivery = delivery
      @message = delivery.message
      @event = @message.event
    end

    def body
      localized do
        lines = [ headline ]
        lines << @message.body.to_s.squish.truncate(240) if @message.body.present?
        lines << "#{t(@event.collects_replies? ? 'details_rsvp' : 'open_card')}: #{@delivery.personal_url}"
        lines << t("stop")
        lines.join("\n").truncate(MAX_LENGTH)
      end
    end

    # The one-line message for template-based channels (WhatsApp templates fill in the link separately).
    def headline_text
      localized { [ headline, (@message.body.to_s.squish.truncate(200) if @message.body.present?) ].compact.join(" ") }
    end

    private
      def headline
        key = @message.kind.presence_in(%w[invitation save_the_date announcement cancellation reminder]) || "update"
        t(key, host: @event.display_host_name, title: @event.title)
      end

      def localized(&)
        I18n.with_locale(@event.locale.presence || I18n.default_locale, &)
      end

      def t(key, **options)
        I18n.t("guest.sms.#{key}", **options)
      end
  end
end
