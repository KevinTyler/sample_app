module EventsHelper
  STATUS_LABELS = { "draft" => "Draft", "published" => "Published", "cancelled" => "Cancelled" }.freeze

  ROLE_LABELS = { "owner" => "Owner", "editor" => "Co-host", "checkin" => "Door staff" }.freeze

  def event_status_badge(event)
    tag.span(STATUS_LABELS.fetch(event.status), class: "badge badge--#{event.status}")
  end

  # "Saturday, November 7, 2026 · 7:00 PM – 10:00 PM EST"
  def event_when(event, with_zone: true)
    return "Date to be announced" unless event.starts_at

    starts = event.local(event.starts_at)
    text = "#{starts.strftime('%A, %B %-d, %Y')} · #{short_time(starts)}"
    if event.ends_at
      ends = event.local(event.ends_at)
      text += ends.to_date == starts.to_date ? " – #{short_time(ends)}" : " – #{ends.strftime('%b %-d')}, #{short_time(ends)}"
    end
    text += " #{starts.strftime('%Z')}" if with_zone
    text
  end

  # Two-line date for the card face: "Saturday, November 7 · 7 PM".
  def card_when(event)
    return "Date to be announced" unless event.starts_at

    starts = event.local(event.starts_at)
    "#{starts.strftime('%A, %B %-d, %Y')} · #{short_time(starts)}"
  end

  def event_date_short(event)
    return "Date TBA" unless event.starts_at

    event.local(event.starts_at).strftime("%a, %b %-d, %Y")
  end

  def short_time(time)
    time.min.zero? ? time.strftime("%-l %p") : time.strftime("%-l:%M %p")
  end

  def event_where(event)
    [ event.location_name, event.address ].compact_blank.join(", ").presence || (event.online? ? "Online" : nil)
  end

  def map_url(event)
    return if event.address.blank? && event.location_name.blank?

    "https://www.openstreetmap.org/search?#{ { query: [ event.location_name, event.address ].compact_blank.join(', ') }.to_query }"
  end

  def deadline_text(event)
    return unless event.rsvp_deadline

    deadline = event.local(event.rsvp_deadline)
    "Please RSVP by #{deadline.strftime('%A, %B %-d')} at #{short_time(deadline)} #{deadline.strftime('%Z')}"
  end

  # IANA identifiers grouped by Rails' friendly names, deduplicated.
  def time_zone_options(selected)
    zones = ActiveSupport::TimeZone.all.uniq { |z| z.tzinfo.name }.map do |zone|
      [ "(GMT#{zone.formatted_offset}) #{zone.name}", zone.tzinfo.name ]
    end
    zones.unshift([ selected, selected ]) if selected.present? && zones.none? { |_, id| id == selected }
    options_for_select(zones, selected)
  end

  SECTIONS = {
    "events" => { "show" => :overview, "edit" => :settings, "update" => :settings, "cancellation" => :settings },
    "guests" => :guests, "guest_imports" => :guests, "event_designs" => :design, "messages" => :mail,
    "questions" => :form, "check_ins" => :scan, "cohosts" => :cohosts
  }.freeze

  def workspace_section
    entry = SECTIONS[controller_name]
    entry.is_a?(Hash) ? entry[action_name] : entry
  end

  def workspace_link(label, path, key, current, count: nil)
    active = key == current
    link_to path, class: [ "side-link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) } do
      safe_join([ icon(key), tag.span(label), (tag.span(count, class: "side-link__count") if count) ].compact)
    end
  end

  # Prefilled share text for messaging apps; the link is the public share page (no personal data).
  def share_blurb(event)
    "You're invited: #{event.title} — #{event_date_short(event)}"
  end

  def share_text(event)
    "#{share_blurb(event)} #{public_event_url(event.share_token)}"
  end

  def percent(part, whole)
    return 0 if whole.to_i.zero?

    ((part.to_f / whole) * 100).round
  end
end
