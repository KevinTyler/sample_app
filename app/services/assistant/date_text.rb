module Assistant
  # "Sat Nov 14 2pm" / "11/14 at 2:30pm" / "2026-11-14 14:00" → a time in the event's zone.
  module DateText
    module_function

    def parse(text, zone:, now: Time.current)
      cleaned = text.to_s.downcase.gsub(/\b(mon|tues?|wed(nes)?|thu(rs)?|fri|sat(ur)?|sun)(day)?\b,?/, " ")
        .gsub(/\b(at|@|from)\b/, " ").gsub(/(\d)\s*(am|pm)\b/, '\1\2').squish
      return if cleaned.empty?

      if cleaned.match?(/\btomorrow\b/)
        base = now.in_time_zone(zone).tomorrow
        cleaned = cleaned.sub("tomorrow", base.strftime("%Y-%m-%d"))
      end
      parts = Date._parse(cleaned)
      return unless parts[:mon] && parts[:mday]

      local_now = now.in_time_zone(zone)
      year = parts[:year] || local_now.year
      time = zone.local(year, parts[:mon], parts[:mday], parts[:hour] || 18, parts[:min] || 0)
      time = time.change(year: year + 1) if parts[:year].nil? && time < local_now.beginning_of_day
      time
    rescue ArgumentError
      nil
    end
  end
end
