# A gift a guest brought (or sent). Only hosts see the gift log.
class Gift < ApplicationRecord
  belongs_to :event
  belongs_to :guest, optional: true
  has_one :thank_you, dependent: :nullify

  normalizes :giver_name, :description, with: ->(v) { v.to_s.squish }

  validates :giver_name, presence: true, length: { maximum: 100 }
  validates :description, presence: true, length: { maximum: 120 }
  validates :notes, length: { maximum: 1000 }
  validate :guest_belongs_to_event

  before_validation { self.giver_name = guest.name if giver_name.blank? && guest }

  def thanked?
    thank_you&.ready?
  end

  private
    def guest_belongs_to_event
      errors.add(:guest, "isn't on this guest list") if guest && guest.event_id != event_id
    end
end
