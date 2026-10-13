# Texts a host on their assistant thread (e.g. "Dana is coming").
class AssistantNotifyJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, text)
    conversation = AssistantConversation.find_by(id: conversation_id)
    conversation.reply!(text) if conversation&.can_message?
  end
end
