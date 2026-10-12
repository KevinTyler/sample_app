module OutboxHelper
  # Escapes text and turns http(s) URLs into links (used to click personal links in captured mail).
  def auto_link_text(text)
    parts = text.to_s.split(%r{(https?://[^\s<>"]+)})
    safe_join(parts.map { |part| part.match?(%r{\Ahttps?://}) ? link_to(part, part) : part })
  end
end
