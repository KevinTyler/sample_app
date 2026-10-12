class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :owned_events, class_name: "Event", foreign_key: :owner_id, inverse_of: :owner, dependent: :destroy
  has_many :event_memberships, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, length: { maximum: 80 }
  validates :email_address, presence: true, length: { maximum: 254 },
    format: { with: EmailFormat::REGEXP }, uniqueness: true
  validates :password, length: { minimum: 10, maximum: 72 }, allow_nil: true

  # Every event this user may open in the host dashboard: owned or co-hosted.
  def accessible_events
    Event.where(owner_id: id).or(Event.where(id: event_memberships.select(:event_id)))
  end

  def first_name
    name.split.first
  end
end
