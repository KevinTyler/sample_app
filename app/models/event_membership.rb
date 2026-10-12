# A co-host's access to an event. The owner is Event#owner, not a membership.
class EventMembership < ApplicationRecord
  ROLES = {
    "editor" => { name: "Co-host", summary: "Edit the event and design, manage guests, send messages, check guests in" },
    "checkin" => { name: "Door staff", summary: "Check guests in only — no contact details or private links" }
  }.freeze

  belongs_to :event
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true

  validates :role, inclusion: { in: ROLES.keys }
  validates :user_id, uniqueness: { scope: :event_id }
  validate :not_the_owner

  def role_name
    ROLES.dig(role, :name)
  end

  private
    def not_the_owner
      errors.add(:user, "already owns this event") if event && user_id == event.owner_id
    end
end
