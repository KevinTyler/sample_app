module Assistant
  # Entry point for texts to the assistant's number (SMS or WhatsApp, via the Twilio webhook or the
  # development simulator): records the message and queues the reply.
  module Inbound
    STOP_WORDS = Webhooks::TwilioController::STOP_WORDS
    START_WORDS = %w[START UNSTOP YES].freeze

    module_function

    # Returns the recorded AssistantMessage, or nil when nothing should be answered.
    def receive(channel:, address:, body:, media: [], provider_message_id: nil, reply_now: false)
      address = PhoneNumber.normalize(address.to_s.delete_prefix("whatsapp:"))
      return unless address && channel.in?(AssistantConversation::CHANNELS)

      conversation = AssistantConversation.for(channel: channel, address: address)
      word = body.to_s.strip.upcase
      if word.in?(STOP_WORDS)
        conversation.update!(opted_out_at: Time.current)
        return
      elsif conversation.opted_out?
        return unless word.in?(START_WORDS)

        conversation.update!(opted_out_at: nil)
      end

      message = conversation.messages.create!(direction: "in", body: body.to_s.first(4000), media: Array(media).first(5),
        provider_message_id: provider_message_id.presence)
      conversation.update!(last_inbound_at: Time.current)
      reply_now ? AssistantReplyJob.perform_now(message.id) : AssistantReplyJob.perform_later(message.id)
      message
    rescue ActiveRecord::RecordNotUnique
      nil # a provider retry of a message we already have
    end
  end
end
