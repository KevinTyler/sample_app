module MessagesHelper
  KIND_LABELS = { "invitation" => "Invitation", "update" => "Update", "reminder" => "Reminder",
                  "cancellation" => "Cancellation", "rsvp_confirmation" => "RSVP link" }.freeze
  DELIVERY_LABELS = { "queued" => "Queued", "sending" => "Sending", "sent" => "Sent", "delivered" => "Delivered",
                      "failed" => "Failed", "bounced" => "Bounced" }.freeze

  def message_kind_badge(message)
    badge = tag.span(KIND_LABELS.fetch(message.kind, message.kind.humanize), class: "badge badge--#{message.kind == 'cancellation' ? 'cancelled' : 'sent'}")
    AutoReminders.auto?(message) ? safe_join([ badge, tag.span("Automatic", class: "tag") ], " ") : badge
  end

  def message_status_text(message)
    case message.status
    when "scheduled" then "Scheduled for #{message.event.local(message.scheduled_for).strftime('%b %-d, %-l:%M %p %Z')}"
    when "dispatched" then "Sent #{time_ago_in_words(message.dispatched_at)} ago"
    else "Sending…"
    end
  end

  def delivery_status_badge(delivery)
    return tag.span("Unconfirmed", class: "badge badge--warning") if delivery.stale?

    css = { "sent" => "sent", "delivered" => "opened", "failed" => "failed", "bounced" => "failed" }.fetch(delivery.status, "queued")
    tag.span(DELIVERY_LABELS.fetch(delivery.status, delivery.status), class: "badge badge--#{css}", title: delivery.error_message)
  end

  def channel_label(channel)
    channel == "sms" ? "Text" : "Email"
  end
end
