module Assistant
  # Entry point for messages to the agent — texts to its number (SMS or WhatsApp, via the Twilio
  # webhook or the development simulator) and messages on the web — records them and queues the reply.
  module Inbound
    STOP_WORDS = Webhooks::TwilioController::STOP_WORDS
    START_WORDS = %w[START UNSTOP YES].freeze
    LINK_CODE = /\A\s*LINK\s+([A-Z0-9]{6})\s*\z/i
    MAX_LINK_ATTEMPTS = 5

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
      return message if link_phone(conversation, body)

      reply_now ? AssistantReplyJob.perform_now(message.id) : AssistantReplyJob.perform_later(message.id)
      message
    rescue ActiveRecord::RecordNotUnique
      nil # a provider retry of a message we already have
    end

    # A message from the signed-in host on the web. `file` is an uploaded file (a guest list,
    # contacts file, photo or video) or nil.
    def receive_web(user:, body:, file: nil)
      conversation = AssistantConversation.for_web(user)
      media = []
      if file.respond_to?(:content_type)
        blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename.to_s.first(120), content_type: file.content_type)
        media << { "url" => "blob:#{blob.signed_id}", "content_type" => blob.content_type, "filename" => blob.filename.to_s }
      end
      text = body.to_s.strip
      return if text.empty? && media.empty?

      message = conversation.messages.create!(direction: "in", body: text.first(8000), media: media)
      conversation.update!(last_inbound_at: Time.current)
      AssistantReplyJob.perform_later(message.id)
      message
    end

    # "LINK 4F7KQ2" texted from a phone connects it to the web account that showed that code.
    def link_phone(conversation, body)
      code = body.to_s[LINK_CODE, 1]
      return false unless code

      attempts = conversation.data_value(:link_attempts).to_i
      if attempts >= MAX_LINK_ATTEMPTS
        conversation.reply!("Too many tries. Get a fresh code on your Cordially page and try again later.")
      elsif conversation.user
        conversation.reply!("This phone is already connected to #{conversation.user.first_name}'s Cordially account.")
      elsif (user = User.claim_phone_link(code))
        conversation.update!(user: user)
        conversation.store!(link_attempts: 0)
        user.update!(agent_reach: "text") if user.agent_reach == "email"
        conversation.reply!("Connected, #{user.first_name}! I'll text you here when something needs you, and you can text me anything — " \
          "it's the same me as on the web. Reply STOP any time.")
      else
        conversation.store!(link_attempts: attempts + 1)
        conversation.reply!("That code didn't work — codes last 15 minutes. Get a fresh one on your Cordially page.")
      end
      true
    end
  end
end
