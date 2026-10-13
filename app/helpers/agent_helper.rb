# The agent's conversation on the web ("Today").
module AgentHelper
  CARD_TYPES = %w[event import proposal link connect_phone].freeze
  # Web addresses, and paths inside Cordially, that the agent mentions become links.
  LINKABLE = %r{https?://[^\s<>"]+|(?<![\w/.])/(?:events|contacts|contact_imports|today|switch|account)\b[^\s<>"]*}

  def agent_greeting(user)
    hour = Time.current.in_time_zone(user.time_zone.presence || "America/New_York").hour
    part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
    "Good #{part}, #{user.first_name}"
  end

  # The agent's words: paragraphs and line breaks kept, links clickable, everything else escaped.
  def agent_text(body)
    paragraphs = body.to_s.strip.split(/\n{2,}/)
    safe_join(paragraphs.map { |para| tag.p(safe_join(para.split("\n").map { |line| linkify(line) }, tag.br)) })
  end

  def render_agent_card(card, conversation)
    type = card["type"].to_s
    return unless type.in?(CARD_TYPES)

    record = case type
    when "event" then current_user.accessible_events.find_by(id: card["event_id"])
    when "import" then current_user.contact_imports.find_by(id: card["import_id"])
    when "proposal" then current_user.agent_proposals.find_by(id: card["proposal_id"])
    when "link" then (card["url"] if card["url"].to_s.match?(%r{\A/(?![/\\])}))
    when "connect_phone" then true
    end
    render("agent/cards/#{type}", record: record, card: card, conversation: conversation) if record
  end

  def event_swatch(event)
    design = InvitationDesign.for(event)
    design.valid? ? design.accent_color : "#8e2b4f"
  end

  def masked_phone(number)
    "•••#{number.to_s.last(4)}"
  end

  private
    def linkify(line)
      parts = []
      last = 0
      line.to_enum(:scan, LINKABLE).each do
        match = Regexp.last_match
        url = match[0].sub(/[.,;:!?)\]]+\z/, "")
        parts << line[last...match.begin(0)]
        parts << link_to(url.delete_prefix("https://").truncate(60), url, rel: "noopener", target: (url.start_with?("http") ? "_blank" : nil))
        parts << match[0][url.length..]
        last = match.end(0)
      end
      parts << line[last..]
      safe_join(parts)
    end
end
