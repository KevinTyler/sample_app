# Postage stamps for the envelope, drawn for Cordially. Each is a small SVG that paints with the
# card's palette (currentColor = accent).
module StampHelper
  STAMP_ART = {
    "heart" => '<path d="M24 36s-11-6.6-11-14.2A6 6 0 0 1 24 18a6 6 0 0 1 11 3.8C35 29.4 24 36 24 36z" fill="currentColor"/>',
    "star" => '<path d="m24 12 3.5 7.4 8 1-5.9 5.5 1.5 8-7.1-3.9-7.1 3.9 1.5-8-5.9-5.5 8-1z" fill="currentColor"/>',
    "flower" => '<g fill="currentColor"><circle cx="24" cy="17" r="5"/><circle cx="31" cy="23" r="5"/><circle cx="28" cy="31" r="5"/><circle cx="20" cy="31" r="5"/><circle cx="17" cy="23" r="5"/></g><circle cx="24" cy="25" r="3.2" fill="#fffdf9"/>',
    "champagne" => '<g fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M17 13h7l-1 9a3 3 0 0 1-5 0zM20.5 25v9M17 34h7"/><path d="M27 15h7l-1 9a3 3 0 0 1-5 0zM30.5 27v7M27 34h7"/></g><circle cx="24" cy="10" r="1.4" fill="currentColor"/><circle cx="29" cy="9" r="1" fill="currentColor"/>',
    "cake" => '<g fill="currentColor"><rect x="14" y="26" width="20" height="10" rx="2"/><rect x="16" y="21" width="16" height="6" rx="2" opacity=".7"/><rect x="23" y="14" width="2" height="7"/></g><path d="M24 10c1.5 1.6 1.5 3.2 0 4-1.5-.8-1.5-2.4 0-4z" fill="currentColor"/>',
    "moon" => '<path d="M29 13a11 11 0 1 0 6 19.5A9 9 0 0 1 29 13z" fill="currentColor"/><circle cx="17" cy="15" r="1" fill="currentColor"/><circle cx="34" cy="20" r="1.2" fill="currentColor"/>',
    "leaf" => '<path d="M14 34c0-12 8-20 21-21-1 13-9 21-21 21z" fill="currentColor"/><path d="M14 34 30 18" stroke="#fffdf9" stroke-width="1.5"/>'
  }.freeze

  def envelope_stamp(key)
    return if key.blank? || key == "none" || !STAMP_ART.key?(key)

    tag.svg(STAMP_ART[key].html_safe, viewBox: "0 0 48 48", class: "envelope__stamp", "aria-hidden": "true", focusable: "false") # rubocop:disable Rails/OutputSafety -- constant markup
  end
end
