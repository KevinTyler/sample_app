module ApplicationHelper
  BRAND = "Larkspur".freeze

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

  def form_errors(record)
    return if record.errors.empty?

    tag.div(class: "form-errors", role: "alert") do
      tag.p("Please fix the following:", class: "form-errors__title") +
        tag.ul(safe_join(record.errors.full_messages.uniq.map { |m| tag.li(m) }))
    end
  end

  def nav_link(label, path, **options)
    active = current_page?(path)
    link_to label, path, class: [ "nav__link", ("is-active" if active) ], aria: { current: (active ? "page" : nil) }, **options
  end
end
