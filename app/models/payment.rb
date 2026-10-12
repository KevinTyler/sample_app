# Money a guest pays for a ticketed event. A payment is created when the guest starts checkout and
# becomes "paid" only when the provider confirms it (Stripe webhook / fake checkout in development).
class Payment < ApplicationRecord
  STATUSES = %w[pending paid failed expired].freeze
  CHECKOUT_REUSE_WINDOW = 23.hours # Stripe Checkout sessions last 24 hours

  belongs_to :event
  belongs_to :guest, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, inclusion: { in: Event::CURRENCIES.keys }
  validates :idempotency_key, presence: true, uniqueness: true

  scope :paid, -> { where(status: "paid") }
  scope :open_checkouts, -> { where(status: "pending").where(created_at: CHECKOUT_REUSE_WINDOW.ago..) }

  # Starts (or resumes) checkout for whatever the guest still owes. Returns nil if nothing is due.
  # Clicking "Pay" twice, or retrying, reuses the same pending payment and checkout session.
  def self.checkout_for!(guest, success_url:, cancel_url:)
    due = guest.amount_due_cents
    return nil unless due.positive?

    event = guest.event
    key = [ "guest", guest.id, guest.party_size, due, guest.amount_paid_cents ].join("-")
    payment = event.payments.find_by(idempotency_key: key)
    if payment.nil?
      payment = event.payments.create!(guest: guest, amount_cents: due, currency: event.currency, quantity: guest.party_size,
        provider: Payments.provider, idempotency_key: key)
    elsif payment.status.in?(%w[expired failed])
      payment.update!(status: "pending", checkout_url: nil, provider_session_id: nil, provider: Payments.provider)
    end
    payment.ensure_checkout!(success_url: success_url, cancel_url: cancel_url) if payment.status == "pending"
    payment
  rescue ActiveRecord::RecordNotUnique
    retry # a concurrent click created it first; pick that one up
  end

  # The row lock makes concurrent clicks wait for, and then reuse, the first checkout session.
  def ensure_checkout!(success_url:, cancel_url:)
    with_lock do
      return if checkout_url.present? && updated_at > CHECKOUT_REUSE_WINDOW.ago

      checkout = Payments.gateway.create_checkout(self, success_url: success_url, cancel_url: cancel_url)
      update!(checkout_url: checkout.url, provider_session_id: checkout.session_id)
    end
  end

  # Idempotent: providers may deliver the same "completed" event more than once.
  def mark_paid!(provider_payment_id: nil)
    claimed = self.class.where(id: id, status: "pending")
      .update_all(status: "paid", paid_at: Time.current, provider_payment_id: provider_payment_id, updated_at: Time.current)
    return false unless claimed == 1

    reload
    Activity.record(event: event, guest: guest, action: "payment_received", data: { amount: amount_cents, currency: currency })
    true
  end

  def mark_expired!
    update!(status: "expired") if status == "pending"
  end

  def amount
    Money.format(amount_cents, currency)
  end

  CHECKOUT_HOSTS = { "stripe" => %w[checkout.stripe.com] }.freeze

  # Defense in depth: only ever send guests to the provider's own checkout host (or, for the
  # development fake, back to this app).
  def safe_checkout_url(app_host:)
    uri = URI.parse(checkout_url.to_s)
    allowed = if provider == "fake"
      uri.host == app_host
    else
      uri.scheme == "https" && CHECKOUT_HOSTS.fetch(provider, []).include?(uri.host)
    end
    allowed ? uri.to_s : nil
  rescue URI::InvalidURIError
    nil
  end
end
