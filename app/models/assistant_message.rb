class AssistantMessage < ApplicationRecord
  belongs_to :conversation, class_name: "AssistantConversation", foreign_key: :assistant_conversation_id, inverse_of: :messages

  validates :direction, inclusion: { in: %w[in out] }

  def inbound?
    direction == "in"
  end

  def media
    Array(super)
  end
end
