module Imports
  # Works out what each column of an imported sheet means — from its heading (in any of the usual
  # spellings: Paperless-Post-style guest lists, Google and Outlook contact exports, vCards, hand-made
  # spreadsheets) and, failing that, from what's in it — then reads out one Person per row, merging
  # rows that are clearly the same person.
  class People
    FIELDS = {
      "name" => "Name", "first_name" => "First name", "last_name" => "Last name", "email" => "Email", "phone" => "Phone",
      "group" => "Group / household", "address" => "Full address", "address_line1" => "Street", "address_line2" => "Apt / unit",
      "city" => "City", "region" => "State / region", "postal_code" => "Postcode / ZIP", "country" => "Country",
      "rsvp" => "RSVP", "party_size" => "Party size", "adults" => "Adults", "kids" => "Kids", "plus_ones" => "Plus-ones allowed",
      "notes" => "Note / message"
    }.freeze

    # Earlier spellings win when several columns could mean the same thing (e.g. Mobile over Home phone).
    ALIASES = {
      "name" => [ "name", "full name", "guest name", "guest", "invitee", "invitee name", "recipient", "recipient name", "addressee",
                  "display name", "contact name", "contact", "attendee", "attendee name", "names" ],
      "first_name" => [ "first name", "given name", "first", "firstname", "forename", "first names" ],
      "last_name" => [ "last name", "family name", "surname", "last", "lastname" ],
      "email" => [ "email", "email address", "e mail", "e mail address", "e mail 1 value", "email 1 value", "primary email",
                   "email 1", "personal email", "mail", "home email", "work email", "e mail 2 address" ],
      "phone" => [ "mobile", "mobile phone", "mobile number", "cell", "cell phone", "phone", "phone number", "phone 1 value",
                   "primary phone", "telephone", "tel", "home phone", "business phone", "phone 2 value" ],
      "group" => [ "group", "groups", "household", "family", "party", "tag", "tags", "label", "labels", "category", "categories",
                   "side", "list", "circle", "group membership", "relationship" ],
      "address" => [ "mailing address", "address", "full address", "home address", "address 1 formatted", "postal address" ],
      "address_line1" => [ "street", "street address", "address 1", "address line 1", "address1", "home street", "address 1 street",
                           "street 1", "mailing street" ],
      "address_line2" => [ "address 2", "address line 2", "address2", "apt", "apartment", "suite", "unit", "home street 2",
                           "address 1 extended address", "street 2" ],
      "city" => [ "city", "town", "home city", "address 1 city", "locality", "city town" ],
      "region" => [ "state", "province", "region", "state province", "home state", "address 1 region", "county", "state region" ],
      "postal_code" => [ "zip", "zip code", "postal code", "postcode", "post code", "home postal code", "address 1 postal code", "zipcode" ],
      "country" => [ "country", "country region", "home country region", "address 1 country", "nation" ],
      "rsvp" => [ "rsvp", "rsvp status", "status", "response", "reply", "attending", "attendance", "will attend", "rsvp response",
                  "rsvp reply", "replied", "reply status", "response status" ],
      "party_size" => [ "party size", "number attending", "total attending", "attending count", "number of guests", "guest count",
                        "total guests", "headcount", "head count", "attendees", "count", "total", "number in party", "guests attending" ],
      "adults" => [ "adults", "adult", "number of adults", "adults attending", "adult count" ],
      "kids" => [ "kids", "children", "child", "number of kids", "number of children", "kids attending", "children attending", "kid count" ],
      "plus_ones" => [ "plus ones", "plus one", "plus ones allowed", "+1", "+1s", "additional guests", "guests allowed", "extra guests",
                       "allowed guests", "max guests" ],
      "notes" => [ "notes", "note", "comments", "comment", "message", "guest message", "rsvp note", "rsvp message", "message to host",
                   "reply note", "rsvp comment" ]
    }.freeze
    LOOKUP = ALIASES.flat_map { |field, names| names.each_with_index.map { |n, rank| [ n, [ field, rank ] ] } }
      .group_by(&:first).transform_values { |pairs| pairs.min_by { |_, (_, rank)| rank }.last }.freeze

    NOT_YET = /\A\s*(no (reply|response|answer)|not (yet )?(replied|responded|opened|viewed|sent|answered)|awaiting|pending|unopened|opened|viewed|sent|delivered|bounced|invited|unanswered)\b/i
    YES = /\A\s*(yes|y|attending|accepted?|going|will attend|confirmed|coming|joyfully accepts?|accepts?|si|sí|oui|sim)\b/i
    NO = /\A\s*(no|n|not attending|not going|declined?|declines|regrets?|regretfully|can'?t|cannot|unable|won'?t|will not)\b/i
    MAYBE = /\A\s*(maybe|tentative|might|possibly|unsure|not sure|perhaps)\b/i
    EMAIL = /\A[^\s@,;<>]+@[^\s@,;<>]+\.[a-z]{2,}\z/i
    PHONE_ISH = /\A\+?[\d\s().\-]{7,20}\z/

    Person = Data.define(:row, :name, :email, :phone, :group, :address, :notes, :rsvp, :party_size, :adults, :kids, :plus_ones) do
      def contact_attributes = { name: name, email: email, phone: phone, household: group, mailing_address: address, notes: notes }.compact_blank
      def replied? = rsvp.in?(%w[yes no maybe])
    end

    attr_reader :sheet, :header_index, :mapping

    # mapping: { column index => field } to override what was detected (from the preview's column pickers).
    def initialize(sheet, mapping: nil, country_code: nil)
      @sheet = sheet
      @country_code = country_code
      @header_index = detect_header_index
      @mapping = mapping ? clean_mapping(mapping) : detect_mapping
    end

    def headers
      header_index ? sheet.rows[header_index] : Array.new(width) { |i| "Column #{i + 1}" }
    end

    def data_rows
      sheet.rows.drop(header_index ? header_index + 1 : 0)
    end

    def width
      sheet.rows.map(&:size).max.to_i
    end

    # A title line above the headings ("Guest list: Maya's 5th") or the file name.
    def title_hint
      above = header_index.to_i.positive? ? sheet.rows.first(header_index).flatten.compact_blank.first : nil
      cleaned = above.to_s.sub(/\A(guest\s*list|guests|rsvps?|tracking)\s*[-–—:|]?\s*(for\s+)?/i, "").squish
      cleaned.presence&.first(120) || sheet.title_hint
    end

    def people
      @people ||= begin
        rows = data_rows.each_with_index.filter_map { |cells, i| person_from(cells, i + 1 + (header_index ? header_index + 1 : 0)) }
        merge_duplicates(rows)
      end
    end

    def has_replies? = mapping.value?("rsvp") && people.any?(&:replied?)
    def has_addresses? = people.any? { |p| p.address.present? }
    def skipped_columns = headers.each_index.reject { |i| mapping.key?(i) }.map { |i| headers[i].presence || "Column #{i + 1}" }.compact_blank

    def groups
      people.filter_map(&:group).tally.sort_by { |name, count| [ -count, name ] }.map(&:first)
    end

    def counts
      {
        "people" => people.size, "emails" => people.count(&:email), "phones" => people.count(&:phone),
        "addresses" => people.count(&:address), "groups" => groups.size, "merged" => @merged.to_i,
        "yes" => people.count { |p| p.rsvp == "yes" }, "no" => people.count { |p| p.rsvp == "no" },
        "maybe" => people.count { |p| p.rsvp == "maybe" }, "pending" => people.count { |p| !p.replied? }
      }
    end

    # What this probably is, for the preview's headline.
    def source_label
      text = (headers + [ sheet.title_hint.to_s ]).join(" ").downcase
      return "Paperless Post guest list" if sheet.rows.first(5).flatten.join(" ").match?(/paperless/i) || sheet.title_hint.to_s.match?(/paperless/i)
      return "Phone or iCloud contacts (vCard)" if sheet.format == :vcard
      return "Google Contacts export" if text.include?("given name") || text.include?("e-mail 1 - value") || text.include?("group membership")
      return "Outlook contacts export" if text.include?("e-mail address") && text.include?("mobile phone")
      return "Guest list with replies" if has_replies?
      return "Pasted list" if sheet.format == :text

      sheet.format.in?(%i[xlsx xls]) ? "Excel spreadsheet" : "Spreadsheet"
    end

    private
      def normalize(value)
        value.to_s.downcase.tr("_", " ").gsub(/[^a-z0-9+]+/, " ").squish
      end

      def detect_header_index
        best = sheet.rows.first(10).each_with_index.map do |cells, i|
          [ i, cells.count { |cell| LOOKUP.key?(normalize(cell)) }, cells.any? { |c| c.match?(EMAIL) } ]
        end.reject { |_, _, has_email| has_email }.max_by { |i, score, _| [ score, -i ] }
        return best[0] if best && best[1] >= 1

        # Headings we don't recognize still look like headings: words above rows of emails/numbers.
        first, second = sheet.rows.first(2)
        contact_ish = ->(cell) { cell.match?(EMAIL) || (cell.match?(PHONE_ISH) && cell.count("0-9") >= 7) }
        0 if first && second && first.none?(&contact_ish) && second.any?(&contact_ish) && first.compact_blank.size >= second.compact_blank.size
      end

      def detect_mapping
        mapping = {}
        if header_index
          candidates = headers.each_with_index.filter_map do |cell, i|
            field, rank = LOOKUP[normalize(cell)]
            [ i, field, rank ] if field
          end
          candidates.group_by { |_, field, _| field }.each_value do |list|
            i, field, = list.min_by { |index, _, rank| [ rank, index ] }
            mapping[i] = field
          end
          # A second reply-ish column full of numbers ("Status" and "# Attending") is the head count.
          candidates.each do |i, field, _|
            next if mapping.key?(i) || field != "rsvp" || mapping.value?("party_size")

            values = data_rows.map { |r| r[i].to_s }.reject(&:empty?).first(50)
            mapping[i] = "party_size" if values.any? && share(values) { |v| v.match?(/\A\d+\z/) } >= 0.8
          end
        end
        infer_from_values(mapping)
        swap_rsvp_and_count(mapping)
        mapping
      end

      # Columns whose heading we didn't recognize, but whose contents are unmistakable.
      def infer_from_values(mapping)
        (0...width).each do |i|
          next if mapping.key?(i)

          values = data_rows.map { |r| r[i].to_s }.reject(&:empty?).first(50)
          next if values.empty?

          if !mapping.value?("email") && share(values) { |v| v.match?(EMAIL) } >= 0.6
            mapping[i] = "email"
          elsif !mapping.value?("phone") && share(values) { |v| v.match?(PHONE_ISH) && v.count("0-9") >= 7 } >= 0.6
            mapping[i] = "phone"
          elsif !mapping.values.intersect?(%w[name first_name]) && header_index.nil? && share(values) { |v| v.match?(/[[:alpha:]]/) && !v.match?(EMAIL) } >= 0.8
            mapping[i] = "name"
          end
        end
      end

      # "# Attending" reads as "attending": numbers mean a head count, words mean a reply.
      def swap_rsvp_and_count(mapping)
        mapping.each do |i, field|
          next unless field.in?(%w[rsvp party_size])

          values = data_rows.map { |r| r[i].to_s }.reject(&:empty?).first(50)
          next if values.empty?

          numeric = share(values) { |v| v.match?(/\A\d+\z/) }
          if field == "rsvp" && numeric >= 0.8 && !mapping.value?("party_size")
            mapping[i] = "party_size"
          elsif field == "party_size" && numeric < 0.2 && share(values) { |v| v.match?(YES) || v.match?(NO) || v.match?(MAYBE) } >= 0.5 && !mapping.value?("rsvp")
            mapping[i] = "rsvp"
          end
        end
      end

      def share(values, &)
        values.count(&).fdiv(values.size)
      end

      def clean_mapping(mapping)
        mapping.to_h.filter_map do |index, field|
          index = Integer(index.to_s, exception: false)
          [ index, field.to_s ] if index && index >= 0 && index < [ width, Reader::MAX_COLUMNS ].min && FIELDS.key?(field.to_s)
        end.uniq { |_, field| field }.to_h
      end

      def person_from(cells, row_number)
        raw = mapping.to_h { |i, field| [ field, cells[i].to_s.strip.presence ] }
        email = raw["email"].to_s.split(/[\s,;]+/).find { |e| e.match?(EMAIL) }&.downcase
        name = raw["name"] || [ raw["first_name"], raw["last_name"] ].compact.join(" ").presence
        name ||= email.to_s.split("@").first.to_s.tr("._-", " ").squish.titleize.presence
        return if name.blank? || name.match?(EMAIL) && email.nil?

        adults = count(raw["adults"])
        kids = count(raw["kids"])
        rsvp = rsvp_value(raw["rsvp"])
        party = count(raw["party_size"]) || ((adults || kids) ? adults.to_i + kids.to_i : nil)
        Person.new(row: row_number, name: name.squish.first(100), email: email, phone: phone(raw["phone"]),
          group: group(raw["group"]), address: address(raw), notes: raw["notes"]&.first(1000), rsvp: rsvp,
          party_size: party, adults: adults, kids: kids, plus_ones: count(raw["plus_ones"]))
      end

      def rsvp_value(value)
        return "pending" if value.blank? || value.match?(NOT_YET)
        return "no" if value.match?(NO)
        return "maybe" if value.match?(MAYBE)
        return "yes" if value.match?(YES) || value.match?(/\A[1-9]\d*\z/)

        "pending" # "No reply", "Opened", "Not opened", "Sent", "Awaiting"…
      end

      def count(value)
        value.to_s[/\d+/]&.to_i&.clamp(0, 50)
      end

      def phone(value)
        return if value.blank?

        first = value.split(%r{\s*(?:[,;/]| ::: )\s*}).find { |v| v.count("0-9") >= 7 }
        PhoneNumber.with_country(first, @country_code)
      end

      # Google writes "Family ::: * myContacts"; keep the first real label.
      def group(value)
        value.to_s.split(/\s*(?::::|[,;|])\s*/).map(&:strip).reject { |g| g.start_with?("*") || g.casecmp?("myContacts") }.first&.first(60)
      end

      def address(raw)
        full = raw["address"]
        parts = [ [ raw["address_line1"], raw["address_line2"] ].compact.join(", ").presence,
                  [ raw["city"], [ raw["region"], raw["postal_code"] ].compact.join(" ").presence ].compact.join(", ").presence,
                  raw["country"] ].compact
        text = parts.size > 1 || full.blank? ? [ full, *parts ].compact.uniq.join("\n") : full
        text.presence&.first(300)
      end

      # Same email (or, without email, the same phone) → one person, details combined.
      def merge_duplicates(people)
        @merged = 0
        by_key = {}
        people.each do |person|
          key = person.email || (person.phone && "tel:#{person.phone}")
          if key && (earlier = by_key[key])
            @merged += 1
            by_key[key] = earlier.with(**person.to_h.except(:row, :name).select { |field, value| value.present? && earlier.public_send(field).blank? })
          else
            by_key[key || "row:#{person.row}"] = person
          end
        end
        by_key.values
      end
  end
end
