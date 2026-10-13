module Assistant
  # "Dana Whitfield 555-0100" / "Lee Park, lee@example.com" per line → guest hashes.
  module GuestText
    EMAIL = /[^\s,;<>]+@[^\s,;<>]+\.[a-z]{2,}/i
    PHONE = /\+?\d[\d\s().-]{6,}\d/

    module_function

    def parse(text)
      text.to_s.split(/\r?\n|;/).filter_map do |line|
        email = line[EMAIL]
        phone = line[PHONE]
        name = line.sub(email.to_s, "").sub(phone.to_s, "").gsub(/[,<>]/, " ").squish
        next if name.empty?

        { name: name, email: email, phone: phone }.compact
      end
    end
  end
end
