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

  # Directions and a ride to the venue — plain links, no API keys or partner deals needed.
  def directions_links(event)
    destination = [ event.location_name, event.address ].compact_blank.join(", ")
    return [] if destination.blank?

    query = ERB::Util.url_encode(destination)
    [
      [ "Google Maps", "https://www.google.com/maps/dir/?api=1&destination=#{query}" ],
      [ "Apple Maps", "https://maps.apple.com/?daddr=#{query}" ],
      [ "Uber", "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff%5Bformatted_address%5D=#{query}" ]
    ]
  end

  def schedule_when(item)
    return "" unless item.starts_at

    starts = item.event.local(item.starts_at)
    text = "#{starts.strftime('%a %b %-d')} · #{short_time(starts)}"
    text += " – #{short_time(item.event.local(item.ends_at))}" if item.ends_at && item.ends_at.to_date == item.starts_at.to_date
    text
  end

  def schedule_checked?(rsvp, item)
    raw = rsvp.respond_to?(:schedule) ? rsvp.schedule : nil
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    value = raw.to_h.transform_keys(&:to_s)[item.id.to_s]
    value.nil? || value.to_s == "1"
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
    "questions" => :form, "check_ins" => :scan, "cohosts" => :cohosts, "thank_yous" => :gift, "gifts" => :gift, "schedule_items" => :calendar
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
