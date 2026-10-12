# A message captured by the local development outbox instead of being sent.
class OutboxItem < ApplicationRecord
  validates :channel, inclusion: { in: %w[email sms] }
  validates :recipient, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
