require "csv"

module Imports
  # Turns whatever a host brings — an Excel download (.xlsx, legacy .xls, or the HTML table some
  # sites save as .xls), CSV/TSV, a vCard (.vcf) from a phone or Google/Outlook, or a list pasted
  # from anywhere — into rows of cell strings. Nothing here knows what the columns mean
  # (that's Imports::People).
  class Reader
    MAX_BYTES = 5.megabytes
    MAX_UNZIPPED_BYTES = 40.megabytes # an .xlsx is a zip; refuse ones that inflate suspiciously
    MAX_ROWS = 5_000
    MAX_COLUMNS = 80
    VCARD_HEADER = [ "Name", "Email", "Phone", "Address", "Groups", "Notes" ].freeze
    FREEFORM_HEADER = [ "Name", "Email", "Phone" ].freeze

    class Unreadable < StandardError; end

    Sheet = Data.define(:rows, :format, :title_hint) do
      def empty? = rows.empty?
    end

    def self.read(data, filename: nil)
      new(data, filename: filename).sheet
    end

    def initialize(data, filename: nil)
      @data = data.to_s.b
      @filename = filename.to_s
    end

    def sheet
      raise Unreadable, "That file is too large (the limit is 5 MB)." if @data.bytesize > MAX_BYTES
      raise Unreadable, "That file is empty." if @data.strip.empty?

      rows, format = if zip? then [ xlsx_rows, :xlsx ]
      elsif ole? then [ xls_rows, :xls ]
      else text_rows
      end
      rows = clean(rows)
      Sheet.new(rows: rows, format: format, title_hint: title_from_filename)
    end

    private
      def zip? = @data.start_with?("PK\x03\x04".b)
      def ole? = @data.start_with?("\xD0\xCF\x11\xE0".b)

      # --- Excel ---------------------------------------------------------------

      def xlsx_rows
        Zip::File.open_buffer(StringIO.new(@data)) do |zip|
          raise Unreadable, "That file doesn't look like an Excel workbook." unless zip.find_entry("xl/workbook.xml")
          raise Unreadable, "That workbook is too large to import." if zip.entries.sum(&:size) > MAX_UNZIPPED_BYTES
        end
        with_tempfile(".xlsx") do |path|
          book = Roo::Excelx.new(path)
          sheet = book.sheet(best_sheet(book))
          rows = []
          sheet.each_row_streaming(pad_cells: true, max_rows: MAX_ROWS + 20) do |cells|
            rows << cells.first(MAX_COLUMNS).map { |cell| cell_text(cell&.value) }
          end
          rows
        end
      rescue Roo::FileNotFound
        plain_xlsx_rows # workbooks written by some web exporters leave out parts Roo expects
      rescue Zip::Error, Roo::Error, Nokogiri::XML::SyntaxError, ArgumentError => e
        raise Unreadable, "We couldn't open that Excel file (#{e.message.truncate(60)}). Try saving it as CSV."
      end

      def xls_rows
        with_tempfile(".xls") do |path|
          book = Roo::Excel.new(path)
          sheet = book.sheet(best_sheet(book))
          return [] unless sheet.first_row

          (sheet.first_row..[ sheet.last_row, sheet.first_row + MAX_ROWS + 20 ].min).map do |i|
            Array(sheet.row(i)).first(MAX_COLUMNS).map { |value| cell_text(value) }
          end
        end
      rescue Ole::Storage::FormatError, Roo::Error, ArgumentError, NoMethodError => e
        raise Unreadable, "We couldn't open that Excel file (#{e.message.truncate(60)}). Try saving it as CSV."
      end

      # Minimal reader for the first worksheet: shared and inline strings, numbers, booleans.
      def plain_xlsx_rows
        rows = []
        # (open_buffer returns the archive, not the block's value)
        Zip::File.open_buffer(StringIO.new(@data)) do |zip|
          read = ->(name) { (entry = zip.find_entry(name)) ? Nokogiri::XML(entry.get_input_stream.read).remove_namespaces! : nil }
          shared = read.("xl/sharedStrings.xml")&.css("si")&.map { |si| si.css("t").map(&:text).join } || []
          sheet = read.("xl/worksheets/sheet1.xml") || raise(Unreadable, "That workbook has no sheets we can read.")
          rows = sheet.css("sheetData row").first(MAX_ROWS + 20).map do |row|
            cells = []
            row.css("c").each do |cell|
              column = cell["r"].to_s[/\A[A-Z]+/].to_s.each_char.reduce(0) { |n, ch| n * 26 + ch.ord - 64 } - 1
              next if column.negative? || column >= MAX_COLUMNS

              value = case cell["t"]
              when "s" then shared[cell.at_css("v")&.text.to_i]
              when "inlineStr" then cell.css("is t").map(&:text).join
              when "b" then cell.at_css("v")&.text == "1" ? "TRUE" : "FALSE"
              else cell_text(cell.at_css("v")&.text&.then { |v| v.match?(/\A-?\d+(\.\d+)?\z/) ? v.to_f : v })
              end
              cells[column] = value.to_s
            end
            cells.map(&:to_s)
          end
        end
        rows
      rescue Zip::Error, Nokogiri::XML::SyntaxError => e
        raise Unreadable, "We couldn't open that Excel file (#{e.message.truncate(60)}). Try saving it as CSV."
      end

      # The sheet with the most filled-in rows (workbooks sometimes open on an empty summary tab).
      def best_sheet(book)
        book.sheets.max_by { |name| book.sheet(name).last_row.to_i } || book.sheets.first
      end

      def cell_text(value)
        case value
        when nil then ""
        when Float then value == value.floor ? value.to_i.to_s : value.to_s
        when Date, Time, DateTime then value.to_s
        else value.to_s.strip
        end
      end

      def with_tempfile(extension)
        Tempfile.create([ "import", extension ], binmode: true) do |file|
          file.write(@data)
          file.flush
          yield file.path
        end
      end

      # --- Text ----------------------------------------------------------------

      def text_rows
        text = utf8(@data).delete_prefix("﻿")
        return [ html_rows(text), :xls ] if text.lstrip.match?(/\A(<!DOCTYPE html|<html|<table|<\?xml[^>]*>\s*<html)/i)
        return [ vcard_rows(text), :vcard ] if text.match?(/^BEGIN:VCARD/i)
        return [ freeform_rows(text), :text ] if freeform?(text)

        [ CSV.parse(text, col_sep: separator(text), liberal_parsing: true).map { |r| Array(r).first(MAX_COLUMNS).map { |c| c.to_s.strip } }, :csv ]
      rescue CSV::MalformedCSVError => e
        raise Unreadable, "That file doesn't look like a valid spreadsheet (#{e.message.truncate(60)})."
      end

      def utf8(bytes)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        return text if text.valid_encoding?

        utf16 = bytes.start_with?("\xFF\xFE".b) || bytes.start_with?("\xFE\xFF".b)
        return bytes.dup.force_encoding(Encoding::UTF_16).encode(Encoding::UTF_8, invalid: :replace, undef: :replace) if utf16

        bytes.dup.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      def separator(text)
        sample = text.lines.first(5).join
        [ ",", "\t", ";", "|" ].max_by { |sep| sample.count(sep) }.then { |sep| sample.count(sep).zero? ? "," : sep }
      end

      def html_rows(text)
        Nokogiri::HTML(text).css("tr").first(MAX_ROWS + 20).map do |tr|
          tr.css("th,td").first(MAX_COLUMNS).map { |cell| cell.text.squish }
        end
      end

      # A pasted list where lines don't share a delimiter: "Dana Whitfield dana@example.com 555 0100".
      def freeform?(text)
        lines = text.lines.map(&:strip).reject(&:empty?).first(20)
        return false if lines.empty?
        # Every line split the same way by a delimiter → it's CSV/TSV, not free text.
        return false if [ ",", "\t", ";" ].any? { |sep| (counts = lines.map { |line| line.count(sep) }).min.positive? && counts.uniq.size == 1 }

        lines.count { |line| line.match?(Assistant::GuestText::EMAIL) || line.match?(Assistant::GuestText::PHONE) } >= (lines.size / 2.0)
      end

      def freeform_rows(text)
        [ FREEFORM_HEADER ] + Assistant::GuestText.parse(text.gsub(/;/, "\n")).map { |p| [ p[:name], p[:email], p[:phone] ].map(&:to_s) }
      end

      # --- vCard -----------------------------------------------------------------

      def vcard_rows(text)
        unfolded = text.gsub(/\r?\n[ \t]/, "")
        cards = unfolded.scan(/^BEGIN:VCARD\s*$(.*?)^END:VCARD/im).first(MAX_ROWS + 1).filter_map do |(body)|
          fields = body.lines.map(&:strip).reject(&:empty?).filter_map do |line|
            key, value = line.split(":", 2)
            next unless value

            name, *params = key.split(";")
            [ name.split(".").last.upcase, params.join(";").downcase, unescape(value) ]
          end
          name = value_of(fields, "FN").presence ||
            value_of(fields, "N").to_s.split(";").values_at(1, 0).compact_blank.join(" ").presence
          email = preferred(fields, "EMAIL")
          next if name.blank? && email.blank?

          [ name.to_s, email.to_s, preferred(fields, "TEL", prefer: /cell|mobile|iphone/).to_s, address(fields),
            value_of(fields, "CATEGORIES").to_s.split(",").first.to_s.strip, value_of(fields, "NOTE").to_s ]
        end
        [ VCARD_HEADER ] + cards
      end

      def value_of(fields, key)
        fields.find { |k, _, _| k == key }&.last
      end

      # The pref/cell entry when there are several (vCards often list home, work and mobile).
      def preferred(fields, key, prefer: /pref/)
        matches = fields.select { |k, _, _| k == key }
        (matches.find { |_, params, _| params.match?(prefer) } || matches.find { |_, params, _| params.include?("pref") } || matches.first)&.last
      end

      # ADR: post-office box; extended; street; locality; region; postal code; country
      def address(fields)
        adr = fields.find { |k, _, _| k == "ADR" }&.last
        return "" unless adr

        _box, extended, street, city, region, postal, country = adr.split(";").map(&:strip)
        [ [ street, extended ].compact_blank.join(", "), [ city, [ region, postal ].compact_blank.join(" ") ].compact_blank.join(", "), country ]
          .compact_blank.join("\n")
      end

      def unescape(value)
        value.gsub("\\n", "\n").gsub(/\\([,;\\])/, '\1').strip
      end

      # --- Shared ------------------------------------------------------------------

      def clean(rows)
        rows.map { |row| row.map { |cell| cell.to_s.gsub(/[[:cntrl:]&&[^\n]]/, "").strip } }
          .reject { |row| row.all?(&:empty?) }
          .first(MAX_ROWS + 20)
      end

      # "Maya's 5th Birthday - Guest List (3).xlsx" → "Maya's 5th Birthday"
      def title_from_filename
        base = File.basename(@filename, ".*").tr("_", " ")
        base = base.tr("-", " ") unless base.include?(" ") # "maya-30th-guest-list"
        base = base.gsub(/\b[a-z]/, &:upcase) if base == base.downcase
        base = base.sub(/\(\d+\)\z/, "").sub(/[-–—:|]?\s*(guest\s*list|guests|rsvps?|tracking|export|contacts|address book)\b.*\z/i, "").squish
        base.presence unless base.match?(/\A(guest\s*list|contacts?|export|download|book\d*|sheet\d*|untitled.*)\z/i)
      end
  end
end
