require "csv"

# A guest-list import from a CSV file or pasted text, in two steps: parse and preview every row
# (new, update, skip, or invalid — with reasons), then apply on confirmation. The raw data is
# erased once the import is applied or discarded.
class GuestImport < ApplicationRecord
  MAX_BYTES = 1.megabyte
  MAX_ROWS = 2_000

  HEADER_ALIASES = {
    name: [ "name", "full name", "guest", "guest name", "guests", "invitee", "household" ],
    first_name: [ "first name", "first", "given name", "firstname" ],
    last_name: [ "last name", "last", "surname", "family name", "lastname" ],
    email: [ "email", "e-mail", "email address", "e-mail address", "mail" ],
    phone: [ "phone", "phone number", "mobile", "cell", "telephone", "tel", "mobile number" ],
    group_name: [ "group", "groups", "tag", "category", "side", "list", "table" ],
    plus_ones_allowed: [ "plus ones", "plus-ones", "plus one", "plus-one", "+1", "+1s", "additional guests", "guests allowed", "extra guests" ],
    host_notes: [ "notes", "note", "comments", "comment" ]
  }.freeze
  POSITIONAL_COLUMNS = %i[name email phone group_name plus_ones_allowed].freeze

  Row = Data.define(:number, :attributes, :status, :messages, :guest) do
    def importable? = status.in?(%i[new update])
  end

  belongs_to :event
  belongs_to :user, optional: true

  validates :status, inclusion: { in: %w[pending completed] }
  validates :csv_data, presence: { message: "is empty — choose a CSV file or paste your list" }, if: :pending?
  validate :within_limits, if: :pending?

  scope :pending, -> { where(status: "pending") }
  scope :stale, -> { pending.where(created_at: ...1.day.ago) }

  def pending?
    status == "pending"
  end

  # Uploads arrive as raw bytes. Store them as UTF-8: as-is when valid, otherwise read as
  # Windows-1252 (what Excel on Windows exports), and drop any byte-order mark.
  def csv_data=(value)
    return super(value) if value.nil?

    text = value.to_s.dup.force_encoding(Encoding::UTF_8)
    text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless text.valid_encoding?
    super(text.delete_prefix("\uFEFF"))
  end

  def rows
    @rows ||= build_rows
  end

  def counts
    rows.group_by(&:status).transform_values(&:size).tap { |c| c.default = 0 }
  end

  def parse_error
    rows
    @parse_error
  end

  # Applies the importable rows. Returns the summary hash.
  def apply!(by: user)
    raise ActiveRecord::RecordInvalid, self unless pending?

    created = updated = 0
    transaction do
      rows.each do |row|
        case row.status
        when :new
          event.guests.create!(row.attributes.merge(source: "csv"))
          created += 1
        when :update
          row.guest.update!(row.attributes.compact_blank.except(:email))
          updated += 1
        end
      end
      skipped = rows.size - created - updated
      update!(status: "completed", csv_data: nil, summary: { "created" => created, "updated" => updated, "skipped" => skipped })
      Activity.record(event: event, user: by, action: "guests_imported", data: summary)
    end
    summary
  end

  private
    def within_limits
      errors.add(:base, "That file is too large (the limit is 1 MB).") if csv_data.to_s.bytesize > MAX_BYTES
      errors.add(:base, "That list has more than #{MAX_ROWS} rows — please split it up.") if rows.size > MAX_ROWS
      errors.add(:base, parse_error) if parse_error
      errors.add(:base, "We couldn't find any guests in that list.") if csv_data.present? && !parse_error && rows.empty?
    end

    def table
      text = csv_data.to_s
      CSV.parse(text, col_sep: detect_separator(text), liberal_parsing: true, skip_blanks: true)
        .reject { |cells| cells.all?(&:blank?) }
    rescue CSV::MalformedCSVError => e
      @parse_error = "That file doesn't look like valid CSV (#{e.message.truncate(80)})."
      []
    end

    def detect_separator(text)
      first_line = text.lines.first.to_s
      [ ",", ";", "\t" ].max_by { |sep| first_line.count(sep) }.then { |sep| first_line.count(sep).zero? ? "," : sep }
    end

    def build_rows
      cells = table
      return [] if cells.empty?

      mapping = header_mapping(cells.first)
      data = mapping ? cells.drop(1) : cells
      mapping ||= POSITIONAL_COLUMNS.each_with_index.to_h { |attr, i| [ i, attr ] }
      offset = cells.size - data.size

      existing = event.guests.where.not(email: nil).index_by(&:email)
      seen = Set.new
      data.first(MAX_ROWS + 1).each_with_index.map do |values, index|
        build_row(index + 1 + offset, extract(values, mapping), existing, seen)
      end
    end

    def header_mapping(header)
      lookup = HEADER_ALIASES.flat_map { |attr, names| names.map { |n| [ normalize_header(n), attr ] } }.to_h
      mapping = header.each_with_index.filter_map do |cell, i|
        attr = lookup[normalize_header(cell)]
        [ i, attr ] if attr
      end.uniq { |_, attr| attr }.to_h
      mapping if (mapping.values & %i[name first_name email]).any?
    end

    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9+]+/, " ").squish
    end

    def extract(values, mapping)
      raw = mapping.to_h { |index, attr| [ attr, values[index].to_s.strip.presence ] }
      name = raw[:name] || [ raw[:first_name], raw[:last_name] ].compact.join(" ").presence
      name ||= raw[:email].to_s.split("@").first.to_s.tr("._-", " ").squish.titleize.presence
      {
        name: name, email: raw[:email], phone: raw[:phone], group_name: raw[:group_name],
        plus_ones_allowed: parse_plus_ones(raw[:plus_ones_allowed]), host_notes: raw[:host_notes]
      }
    end

    def parse_plus_ones(value)
      return event.default_plus_ones if value.blank?
      return 1 if value.match?(/\A(y|yes|true|\+1)\z/i)
      return 0 if value.match?(/\A(n|no|false|none)\z/i)

      value[/\d+/]&.to_i || event.default_plus_ones
    end

    def build_row(number, attributes, existing, seen)
      guest = Guest.new(attributes.merge(event: event))
      email = guest.email # normalized
      return Row.new(number, attributes, :duplicate_in_file, [ "Same email appears earlier in this list" ], nil) if email && seen.include?(email)

      seen << email if email
      if email && (match = existing[email])
        return Row.new(number, attributes, :exists, [ "Already on your list — skipped" ], match) unless update_existing

        match.assign_attributes(attributes.compact_blank.except(:email))
        return Row.new(number, attributes, :invalid, match.errors.full_messages, nil) unless match.valid?

        return Row.new(number, attributes, :update, [ "Already on your list — details will be updated" ], match)
      end

      guest.validate
      messages = guest.errors.full_messages
      Row.new(number, attributes, messages.empty? ? :new : :invalid, messages, nil)
    end
end
