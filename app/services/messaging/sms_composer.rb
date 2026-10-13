module Messaging
  # Builds the short plain-text body for SMS deliveries.
  class SmsComposer
    MAX_LENGTH = 480 # ~3 SMS segments

    def initialize(delivery)
      @delivery = delivery
      @message = delivery.message
      @event = @message.event
    end

    def body
      lines = [ headline ]
      lines << @message.body.to_s.squish.truncate(240) if @message.body.present?
      lines << "#{@event.collects_replies? ? 'Details & RSVP' : 'Open the card'}: #{@delivery.personal_url}"
      lines << "Reply STOP to opt out."
      lines.join("\n").truncate(MAX_LENGTH)
    end

    # The one-line message for template-based channels (WhatsApp templates fill in the link separately).
    def headline_text
      [ headline, (@message.body.to_s.squish.truncate(200) if @message.body.present?) ].compact.join(" ")
    end

    private
      def headline
        case @message.kind
        when "invitation" then "#{@event.display_host_name} invited you to #{@event.title}."
        when "save_the_date" then "Save the date! #{@event.display_host_name}: #{@event.title}."
        when "announcement" then "News from #{@event.display_host_name}: #{@event.title}."
        when "cancellation" then "#{@event.title} has been cancelled."
        when "reminder" then "Reminder: #{@event.title}"
        else "Update about #{@event.title}"
        end
      end
  end
end
