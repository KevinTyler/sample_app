# Answers one text to the assistant. If the host has sent more texts since, only the newest one is
# answered (with the whole thread as context), so a burst of texts gets one reply.
class AssistantReplyJob < ApplicationJob
  queue_as :default

  TROUBLE = "Sorry — I'm having trouble right now. Please try again in a minute.".freeze
  OVER_LIMIT = "You've sent a lot of messages today! I'll be back tomorrow — or open Cordially on the web any time.".freeze

  def perform(message_id)
    message = AssistantMessage.find_by(id: message_id)
    return unless message&.inbound?

    conversation = message.conversation
    return if conversation.opted_out? || conversation.latest_inbound != message
    return conversation.reply!(OVER_LIMIT) if conversation.over_daily_limit?

    brain = Assistant.brain_for(conversation, message)
    text = brain.reply
    conversation.reply!(text, cards: brain.cards)
  rescue Anthropic::Errors::APIError => e
    Rails.logger.error("[assistant] Claude API error: #{e.class}: #{e.message}")
    conversation&.reply!(TROUBLE)
  end
end
