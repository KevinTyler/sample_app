module Messaging
  module Whatsapp
    # Development/test WhatsApp "provider": records the message in the local Outbox.
    module OutboxAdapter
      module_function

      def configured?
        true
      end

      def deliver(delivery)
        send_text(to: delivery.recipient, body: SmsComposer.new(delivery).body, metadata: { delivery_id: delivery.id })
      end

      def send_text(to:, body:, media_urls: [], metadata: {})
        item = OutboxItem.create!(channel: "whatsapp", recipient: to, text_body: [ body, *media_urls.map { |u| "[media] #{u}" } ].join("\n"),
          metadata: metadata)
        Receipt.new(provider: "outbox", message_id: "outbox-#{item.id}")
      end
    end
  end
end
