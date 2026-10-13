# Keeps the automatic reminders an event's settings ask for in step with its dates.
#
# Each reminder is an ordinary scheduled Message with a fixed idempotency key, so syncing is
# repeatable: it creates, moves or withdraws the message as settings and dates change, and never
# touches one that has already gone out. Hosts see (and can cancel) them in Messages.
class AutoReminders
  NUDGE_KEY = "auto-nudge"
  DAY_BEFORE_KEY = "auto-day-before"
  KEYS = [ NUDGE_KEY, DAY_BEFORE_KEY ].freeze
  SEND_HOUR = 10 # local time at the event

  def self.sync(event)
    new(event).sync
  end

  def self.auto?(message)
    message.idempotency_key.in?(KEYS)
  end

  def initialize(event)
    @event = event
  end

  def sync
    sync_one(NUDGE_KEY, nudge_at, audience: { "statuses" => [ "pending" ] },
      subject: "Can you make it? #{@event.title}",
      body: "We'd love to know if you can make it#{deadline_phrase}. Tap your invitation link to reply — it only takes a moment.")
    sync_one(DAY_BEFORE_KEY, day_before_at, audience: { "statuses" => %w[yes maybe] },
      subject: "See you tomorrow: #{@event.title}",
      body: "Just a reminder that #{@event.title} is tomorrow. Your invitation has the time, place and everything else you need.")
  end

  private
    def nudge_at
      return unless @event.auto_nudge? && @event.published? && (closes = @event.rsvp_closes_at)

      at_send_hour(closes - @event.nudge_days_before.days)
    end

    def day_before_at
      return unless @event.auto_day_before? && @event.published? && @event.starts_at

      at_send_hour(@event.starts_at - 1.day)
    end

    def at_send_hour(time)
      @event.local(time).change(hour: SEND_HOUR)
    end

    def deadline_phrase
      return "" unless @event.rsvp_deadline

      " — replies close #{@event.local(@event.rsvp_deadline).strftime('%A, %B %-d')}"
    end

    def sync_one(key, at, **attributes)
      message = @event.messages.find_by(idempotency_key: key)
      if at.nil? || at <= Time.current
        message.destroy! if message&.scheduled?
      elsif message.nil?
        @event.messages.create!(idempotency_key: key, kind: "reminder", status: "scheduled", scheduled_for: at,
          channels: %w[email], **attributes).enqueue_scheduled_dispatch
      elsif message.scheduled? && message.scheduled_for != at
        message.update!(scheduled_for: at, **attributes.slice(:subject, :body))
        message.enqueue_scheduled_dispatch
      end
    end
end
