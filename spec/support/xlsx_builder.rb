require "zip"

# Builds a minimal real .xlsx workbook (one sheet, inline strings) for import specs.
module XlsxBuilder
  def xlsx_from(rows, sheet_name: "Guests")
    escape = ->(v) { v.to_s.encode(xml: :text) }
    sheet_rows = rows.each_with_index.map do |cells, r|
      xml = cells.each_with_index.map do |value, c|
        ref = "#{(65 + c).chr}#{r + 1}"
        value.is_a?(Numeric) ? %(<c r="#{ref}"><v>#{value}</v></c>) : %(<c r="#{ref}" t="inlineStr"><is><t>#{escape.(value)}</t></is></c>)
      end.join
      %(<row r="#{r + 1}">#{xml}</row>)
    end.join
    files = {
      "[Content_Types].xml" => %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>),
      "_rels/.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>),
      "xl/workbook.xml" => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="#{escape.(sheet_name)}" sheetId="1" r:id="rId1"/></sheets></workbook>),
      "xl/_rels/workbook.xml.rels" => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>),
      "xl/worksheets/sheet1.xml" => %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)
    }
    buffer = Zip::OutputStream.write_buffer do |zip|
      files.each { |name, body| zip.put_next_entry(name); zip.write(body) }
    end
    buffer.string
  end
end

RSpec.configure { |config| config.include XlsxBuilder } if defined?(RSpec.configure)
