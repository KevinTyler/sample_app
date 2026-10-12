module Messaging
  module Sms
    # Development/test SMS "provider": records the text in the local Outbox.
    module OutboxAdapter
      module_function

      def configured?
        true
      end

      def deliver(delivery)
        item = OutboxItem.create!(channel: "sms", recipient: delivery.recipient,
          text_body: SmsComposer.new(delivery).body, metadata: { delivery_id: delivery.id })
        Receipt.new(provider: "outbox", message_id: "outbox-#{item.id}")
      end
    end
  end
end
