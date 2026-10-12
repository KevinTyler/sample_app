# One message to one guest over one channel.
#
#   queued ──claim──▶ sending ──▶ sent
#                        │
#                        └──▶ failed ──(retry/claim)──▶ sending …
#
# The claim is an atomic conditional UPDATE, so two workers (or a job retry racing a
# manual retry) can never both send the same delivery. If a worker dies mid-send the row
# stays in "sending" and is surfaced to the host as "unconfirmed" rather than being
# re-sent automatically — we prefer at-most-once for guest-facing messages.
class Delivery < ApplicationRecord
  STATUSES = %w[queued sending sent delivered failed bounced].freeze
  LIVE_STATUSES = %w[queued sending sent delivered].freeze
  CLAIMABLE_STATUSES = %w[queued failed].freeze
  MAX_ATTEMPTS = 5
  STALE_SENDING_AFTER = 15.minutes

  class TransientError < StandardError; end
  class PermanentError < StandardError; end

  belongs_to :message
  belongs_to :guest

  validates :channel, inclusion: { in: Message::CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :recipient, presence: true

  delegate :event, to: :message

  def deliver_now!
    return false unless claim!

    begin
      receipt = Messaging.gateway_for(channel).deliver(self)
    rescue PermanentError => e
      mark_failed!(e)
      return false
    rescue StandardError => e
      mark_failed!(e)
      raise TransientError, e.message if attempts < MAX_ATTEMPTS

      return false
    end

    # Deliberately outside the rescue above: if recording success fails, the row stays in
    # "sending" (shown as unconfirmed) instead of being retried and sent twice.
    mark_sent!(receipt)
    true
  end

  # Atomically moves queued/failed → sending. Returns true only for the caller that won.
  def claim!
    now = Time.current
    claimed = self.class.where(id: id, status: CLAIMABLE_STATUSES)
      .update_all([ "status = 'sending', attempts = attempts + 1, last_attempt_at = ?, updated_at = ?", now, now ])
    reload if claimed == 1
    claimed == 1
  end

  def mark_sent!(receipt)
    update!(status: "sent", sent_at: Time.current, provider: receipt.provider,
      provider_message_id: receipt.message_id, error_message: nil)
    guest.update_column(:invited_at, sent_at) if message.kind == "invitation" && guest.invited_at.nil?
  end

  def mark_failed!(error)
    update_columns(status: "failed", error_message: error.message.to_s.truncate(250), updated_at: Time.current)
  end

  # Provider feedback (webhooks). Only moves forward: a late "delivered" can't undo a bounce.
  def record_provider_event!(event, reason: nil)
    case event
    when :delivered
      update!(status: "delivered", delivered_at: Time.current) if status == "sent"
    when :bounced, :failed
      update!(status: event == :bounced ? "bounced" : "failed", error_message: reason.to_s.truncate(250).presence || "Rejected by the recipient's server")
    when :complained
      guest.update!(unsubscribed_at: Time.current) unless guest.unsubscribed?
    end
  end

  def stale?
    status == "sending" && last_attempt_at && last_attempt_at < STALE_SENDING_AFTER.ago
  end

  # Host-initiated retry of a failed delivery.
  def retry!
    return false unless status == "failed"

    DeliveryJob.perform_later(id)
    true
  end

  def personal_url
    Rails.application.routes.url_helpers.guest_invitation_url(guest.access_token, **Messaging.url_options)
  end
end
