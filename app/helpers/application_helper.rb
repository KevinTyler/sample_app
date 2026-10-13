module ApplicationHelper
  BRAND = "Cordially".freeze

  # Returns a title on a per-page basis (kept from the original sample app).
  def title
    page = content_for(:title)
    page.present? ? "#{page} · #{BRAND}" : "#{BRAND} — invitations & RSVPs"
  end

  def flash_messages
    safe_join(flash.to_hash.slice("notice", "alert").map do |type, message|
      tag.div(message, class: "flash flash--#{type}", role: type == "alert" ? "alert" : "status")
    end)
  end

  # `full: false` lists bare messages, for models whose messages are already whole sentences.
  def form_errors(record, title: "Please fix the following:", full: true)
    return if record.errors.empty?

    messages = full ? record.errors.full_messages : record.errors.map(&:message)
    tag.div(class: "form-errors", role: "alert") do
      tag.p(title, class: "form-errors__title") +
        tag.ul(safe_join(messages.uniq.map { |m| tag.li(m) }))
    end
  end

  # Guest-facing text, in the event's language (see config/locales/guest.*.yml).
  def gt(key, **options)
    t("guest.#{key}", **options)
  end

  def nav_link(label, path, active: current_page?(path), **options)
    link_to label, path, class: [ "app-nav__link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) }, **options
  end

  # Two-letter monogram for avatars and guest rows: "Dana Whitfield" → "DW".
  def initials(name)
    parts = name.to_s.scan(/[[:alpha:]][[:alpha:]'’-]*/)
    return "?" if parts.empty?

    (parts.size == 1 ? parts.first.first(2) : parts.first.first + parts.last.first).upcase
  end
end
