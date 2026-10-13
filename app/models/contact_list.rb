require "csv"

# Reads people out of a CSV/spreadsheet export or a vCard file (.vcf, as exported by iPhone,
# Android, Google and Outlook contacts). Returns plain hashes; callers validate and save.
class ContactList
  MAX_BYTES = 2.megabytes
  MAX_ROWS = GuestImport::MAX_ROWS

  attr_reader :error

  def initialize(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace) unless text.valid_encoding?
    @text = text.delete_prefix("﻿")
  end

  def people
    @people ||= if @text.bytesize > MAX_BYTES
      @error = "That file is too large (the limit is 2 MB)."
      []
    elsif @text.match?(/^BEGIN:VCARD/i)
      vcards
    else
      csv_rows
    end.first(MAX_ROWS)
  end

  private
    # --- vCard -------------------------------------------------------------

    def vcards
      unfolded = @text.gsub(/\r?\n[ \t]/, "")
      unfolded.scan(/^BEGIN:VCARD\s*$(.*?)^END:VCARD/im).filter_map do |(body)|
        fields = body.lines.map(&:strip).reject(&:empty?).filter_map do |line|
          key, value = line.split(":", 2)
          next unless value

          [ key.split(";").first.split(".").last.upcase, unescape(value) ]
        end
        name = fields.find { |k, _| k == "FN" }&.last.presence ||
          fields.find { |k, _| k == "N" }&.last.to_s.split(";").values_at(1, 0).compact_blank.join(" ").presence
        email = fields.find { |k, _| k == "EMAIL" }&.last
        phone = fields.find { |k, _| k == "TEL" }&.last
        next if name.blank? && email.blank?

        { name: name || email.to_s.split("@").first, email: email, phone: phone, household: nil,
          notes: fields.find { |k, _| k == "NOTE" }&.last }
      end
    end

    def unescape(value)
      value.gsub("\\n", "\n").gsub(/\\([,;\\])/, '\1').strip
    end

    # --- CSV ---------------------------------------------------------------

    ALIASES = GuestImport::HEADER_ALIASES.merge(
      household: [ "household", "family", "group", "groups", "tag", "category", "side" ],
      notes: [ "notes", "note", "comments", "comment" ]
    ).except(:group_name, :host_notes, :plus_ones_allowed).freeze

    def csv_rows
      table = CSV.parse(@text, col_sep: separator, liberal_parsing: true, skip_blanks: true).reject { |r| r.all?(&:blank?) }
      return [] if table.empty?

      mapping = header_mapping(table.first)
      data = mapping ? table.drop(1) : table
      mapping ||= { 0 => :name, 1 => :email, 2 => :phone, 3 => :household }
      data.filter_map do |values|
        raw = mapping.to_h { |index, attr| [ attr, values[index].to_s.strip.presence ] }
        name = raw[:name] || [ raw[:first_name], raw[:last_name] ].compact.join(" ").presence ||
          raw[:email].to_s.split("@").first.to_s.tr("._-", " ").squish.titleize.presence
        next unless name

        { name: name, email: raw[:email], phone: raw[:phone], household: raw[:household], notes: raw[:notes] }
      end
    rescue CSV::MalformedCSVError => e
      @error = "That file doesn't look like valid CSV (#{e.message.truncate(80)})."
      []
    end

    def separator
      first = @text.lines.first.to_s
      [ ",", ";", "\t" ].max_by { |s| first.count(s) }.then { |s| first.count(s).zero? ? "," : s }
    end

    def header_mapping(header)
      lookup = ALIASES.flat_map { |attr, names| names.map { |n| [ n.downcase.gsub(/[^a-z0-9+]+/, " ").squish, attr ] } }.to_h
      mapping = header.each_with_index.filter_map do |cell, i|
        attr = lookup[cell.to_s.downcase.gsub(/[^a-z0-9+]+/, " ").squish]
        [ i, attr ] if attr
      end.uniq { |_, attr| attr }.to_h
      mapping if (mapping.values & %i[name first_name email]).any?
    end
end
