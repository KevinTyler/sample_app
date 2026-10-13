# A note an invited guest leaves on the invitation page, visible to the event's other invited
# guests (never on the public share page). Hosts can hide entries.
class GuestbookEntry < ApplicationRecord
  belongs_to :event
  belongs_to :guest, optional: true

  normalizes :body, with: ->(v) { v.to_s.strip }
  normalizes :author_name, with: ->(v) { v.to_s.squish }

  validates :author_name, presence: true, length: { maximum: 100 }
  validates :body, presence: { message: "can't be empty" }, length: { maximum: 500 }

  scope :visible, -> { where(hidden_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def hidden?
    hidden_at.present?
  end
end
