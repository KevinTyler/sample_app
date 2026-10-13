module RsvpHelper
  STATUS_LABELS = { "pending" => "Awaiting reply", "yes" => "Attending", "no" => "Declined", "maybe" => "Maybe" }.freeze
  SENT_PHRASES = { "invitation" => "invitations", "save_the_date" => "save-the-dates", "announcement" => "the announcement",
                   "update" => "an update", "reminder" => "a reminder", "cancellation" => "a cancellation notice" }.freeze
  REPLY_PHRASES = { "yes" => "is coming", "no" => "can't make it", "maybe" => "might come", "pending" => "hasn't decided" }.freeze
  GUEST_CHOICE_LABELS = { "yes" => "Joyfully accepts", "maybe" => "Maybe", "no" => "Regretfully declines" }.freeze

  def rsvp_badge(status)
    tag.span(STATUS_LABELS.fetch(status.to_s, status.to_s.humanize), class: "badge badge--rsvp-#{status}")
  end

  # The host-facing delivery column: what happened to this guest's invitation?
  def delivery_badge(guest)
    delivery = guest.deliveries.select { |d| d.message&.kind.in?(Message::CARD_KINDS) }.max_by(&:created_at)
    if guest.first_viewed_at
      tag.span("Opened", class: "badge badge--opened", title: "First opened #{time_ago_in_words(guest.first_viewed_at)} ago")
    elsif delivery.nil?
      tag.span(guest.email.present? ? "Not sent" : "No email", class: "badge badge--muted")
    elsif delivery.status == "failed"
      tag.span("Failed", class: "badge badge--failed", title: delivery.error_message)
    elsif delivery.status == "bounced"
      tag.span("Bounced", class: "badge badge--failed")
    elsif delivery.stale?
      tag.span("Unconfirmed", class: "badge badge--warning", title: "The send didn't confirm. Check your email provider before resending.")
    elsif delivery.status == "sent"
      tag.span("Sent", class: "badge badge--sent", title: "Sent #{time_ago_in_words(delivery.sent_at)} ago")
    else
      tag.span("Sending…", class: "badge badge--queued")
    end
  end

  def party_label(guest)
    return "—" unless guest.rsvp_yes? || guest.rsvp_maybe?

    guest.party_breakdown
  end

  def activity_sentence(activity)
    data = activity.data || {}
    name = activity.actor_name
    case activity.action
    when "rsvp_submitted" then "#{name} #{REPLY_PHRASES.fetch(data['to'], 'replied')}#{party_suffix(data)}"
    when "rsvp_changed" then "#{name} changed their reply: now #{REPLY_PHRASES.fetch(data['to'], 'replied').delete_prefix('is ')}#{party_suffix(data)}"
    when "viewed" then "#{name} opened the invitation"
    when "guest_added" then "#{name} was added to the guest list"
    when "event_created" then "#{name} created the event"
    when "event_published" then "#{name} published the event"
    when "event_cancelled" then "#{name} cancelled the event"
    when "message_sent" then "#{name} sent #{SENT_PHRASES.fetch(data['kind'], "a #{data['kind']}")} to #{pluralize(data['recipients'], 'guest')}"
    when "guests_imported" then "#{name} imported #{pluralize(data['created'], 'guest')}"
    when "cohost_joined" then "#{name} joined as #{EventMembership::ROLES.dig(data['role'], :name).to_s.downcase}"
    when "guestbook_signed" then "#{name} signed the guestbook"
    when "thank_you_sent" then "Thank-you sent to #{data['name']}"
    when "thank_you_viewed" then "#{data['name']} opened their thank-you"
    when "thank_you_hearted" then "#{data['name']} sent a heart for their thank-you"
    when "check_in_undone" then "#{name}'s check-in was undone"
    when "payment_received" then "#{name} paid #{Money.format(data['amount'], data['currency'])}"
    when "checked_in" then "#{name} checked in#{data['count'].to_i > 1 ? " (party of #{data['count']})" : ''}"
    else activity.action.humanize
    end
  end

  private
    def party_suffix(data)
      data["to"] == "yes" && data["party_size"].to_i > 1 ? " (party of #{data['party_size']})" : ""
    end
end
