# Lightweight audit trail shown on the event dashboard ("Dana changed her RSVP to Yes").
# Data stored here should be non-sensitive: statuses and counts, never contact details.
class Activity < ApplicationRecord
  belongs_to :event
  belongs_to :guest, optional: true
  belongs_to :user, optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record(event:, action:, guest: nil, user: nil, data: {})
    create!(event: event, guest: guest, user: user, action: action, data: data)
  end

  def actor_name
    guest&.name || user&.name || "Someone"
  end
end
