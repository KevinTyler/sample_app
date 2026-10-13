# Someone in a host's address book. Contacts are private to their owner; adding one to an event
# creates a fresh Guest (with its own private link), so nothing about other events leaks across.
class Contact < ApplicationRecord
  MAX_PER_USER = 5_000

  belongs_to :user

  normalizes :name, with: ->(v) { v.squish }
  normalizes :email, with: ->(v) { v.strip.downcase.presence }
  normalizes :phone, with: ->(v) { PhoneNumber.normalize(v) }
  normalizes :household, with: ->(v) { v.squish.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :email, length: { maximum: 254 }, format: { with: EmailFormat::REGEXP }, allow_nil: true
  validates :email, uniqueness: { scope: :user_id, message: "is already in your contacts" }, allow_nil: true
  validates :phone, format: { with: PhoneNumber::FORMAT, message: "should contain 7–15 digits, optionally starting with +" }, allow_nil: true
  validates :household, length: { maximum: 60 }
  validates :notes, length: { maximum: 2000 }
  validate :within_limit, on: :create

  scope :alphabetical, -> { order(Arel.sql("LOWER(contacts.name)")) }
  scope :search, ->(query) {
    term = "%#{sanitize_sql_like(query.to_s.strip.downcase)}%"
    where("LOWER(contacts.name) LIKE :t OR contacts.email LIKE :t OR contacts.phone LIKE :t OR LOWER(contacts.household) LIKE :t", t: term)
  }

  # Adds or refreshes a contact from someone the host just put on a guest list. Never overwrites
  # details the host already has with blanks.
  def self.remember!(user, name:, email: nil, phone: nil, household: nil)
    contact = (email.present? && user.contacts.find_by(email: email.to_s.strip.downcase)) || user.contacts.new
    contact.assign_attributes({ name: name, email: email, phone: phone, household: household }.compact_blank.reject { |k, _| k == :name && contact.persisted? })
    contact.save ? contact : nil
  end

  def guest_attributes
    { name: name, email: email, phone: phone, group_name: household }
  end

  private
    def within_limit
      errors.add(:base, "You can keep up to #{MAX_PER_USER} contacts") if user && user.contacts.count >= MAX_PER_USER
    end
end
