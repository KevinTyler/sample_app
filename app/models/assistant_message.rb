class AssistantMessage < ApplicationRecord
  belongs_to :conversation, class_name: "AssistantConversation", foreign_key: :assistant_conversation_id, inverse_of: :messages

  validates :direction, inclusion: { in: %w[in out] }

  def inbound?
    direction == "in"
  end

  def media
    Array(super)
  end

  def cards
    Array(super)
  end

  # Spreadsheets and contact cards (as opposed to photos and videos for thank-yous).
  def import_files
    media.select { |item| Assistant::Media.importable?(item) }
  end

  def photos_and_videos
    media.reject { |item| Assistant::Media.importable?(item) }
  end
end
