class RsvpAnswer < ApplicationRecord
  belongs_to :guest
  belongs_to :event_question

  validates :event_question_id, uniqueness: { scope: :guest_id }
end
