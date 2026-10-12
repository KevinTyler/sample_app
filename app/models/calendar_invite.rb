# Builds an iCalendar (.ics) file and "add to calendar" links for an event.
# Times are emitted in UTC, which every calendar client converts to the viewer's zone.
class CalendarInvite
  PRODID = "-//Larkspur//Invitations//EN".freeze

  # include_private: false leaves out the video-call link (for the public share page).
  def initialize(event, url: nil, include_private: true)
    @event = event
    @url = url
    @include_private = include_private
  end

  def to_ics
    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:#{PRODID}",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{uid}",
      "DTSTAMP:#{utc(Time.current)}",
      "DTSTART:#{utc(@event.starts_at)}",
      "DTEND:#{utc(@event.effective_ends_at)}",
      "SEQUENCE:#{@event.calendar_sequence}",
      "STATUS:#{@event.cancelled? ? 'CANCELLED' : 'CONFIRMED'}",
      "SUMMARY:#{escape(summary)}",
      ("LOCATION:#{escape(location)}" if location.present?),
      "DESCRIPTION:#{escape(details)}",
      ("URL:#{escape(@url)}" if @url),
      "END:VEVENT",
      "END:VCALENDAR"
    ].compact
    lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
  end

  def google_url
    params = {
      action: "TEMPLATE", text: summary, details: details, location: location.to_s,
      dates: "#{utc(@event.starts_at)}/#{utc(@event.effective_ends_at)}", ctz: @event.time_zone
    }
    "https://calendar.google.com/calendar/render?#{params.to_query}"
  end

  def outlook_url
    params = {
      path: "/calendar/action/compose", rru: "addevent", subject: summary, body: details, location: location.to_s,
      startdt: @event.starts_at.utc.iso8601, enddt: @event.effective_ends_at.utc.iso8601
    }
    "https://outlook.live.com/calendar/0/deeplink/compose?#{params.to_query}"
  end

  def filename
    "#{@event.title.parameterize.presence || 'event'}.ics"
  end

  private
    def uid
      "event-#{@event.id}-#{@event.share_token.first(8)}@larkspur"
    end

    def summary
      @event.cancelled? ? "CANCELLED: #{@event.title}" : @event.title
    end

    def location
      [ @event.location_name, @event.address, (@event.video_url if @include_private) ].compact_blank.join(", ")
    end

    def details
      parts = []
      parts << @event.description.to_s.truncate(1500) if @event.description.present?
      parts << "Join online: #{@event.video_url}" if @event.video_url.present? && @include_private
      parts << "Details & RSVP: #{@url}" if @url
      parts.join("\n\n")
    end

    def utc(time)
      time.utc.strftime("%Y%m%dT%H%M%SZ")
    end

    def escape(text)
      text.to_s.gsub("\\", "\\\\\\\\").gsub(";", "\\;").gsub(",", "\\,").gsub(/\r?\n/, "\\n")
    end

    # RFC 5545: lines longer than 75 octets are folded with CRLF + a single space.
    def fold(line)
      return line if line.bytesize <= 75

      chunks = []
      current = +""
      line.each_char do |char|
        if (current.bytesize + char.bytesize) > (chunks.empty? ? 75 : 74)
          chunks << current
          current = +""
        end
        current << char
      end
      chunks << current
      chunks.join("\r\n ")
    end
end
