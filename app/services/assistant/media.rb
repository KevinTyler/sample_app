module Assistant
  # Files hosts send the agent: photos and videos (e.g. a kid's thank-you video) and guest lists —
  # spreadsheets and contact cards, by WhatsApp document, MMS vCard, or upload on the web.
  module Media
    MAX_BYTES = ThankYou::MEDIA_MAX_SIZE
    IMPORT_TYPES = %w[text/vcard text/x-vcard text/directory text/csv text/comma-separated-values text/tab-separated-values text/plain
                      application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/csv].freeze
    IMPORT_EXTENSIONS = %w[.vcf .vcard .csv .tsv .txt .xls .xlsx].freeze

    module_function

    def importable?(item)
      type = item["content_type"].to_s.split(";").first.to_s.strip.downcase
      type.in?(IMPORT_TYPES) || File.extname(item["filename"].to_s.downcase).in?(IMPORT_EXTENSIONS)
    end

    def fetch(url, content_type:, max_bytes: MAX_BYTES)
      if url.to_s.start_with?("outbox:", "blob:")
        # Uploaded on the web (or in the development simulator) straight into Active Storage.
        blob = ActiveStorage::Blob.find_signed!(url.sub(/\A(outbox|blob):/, ""))
        raise Error, "That file is too large." if blob.byte_size > max_bytes

        return [ blob.download, blob.content_type ]
      end

      data, type = Messaging::TwilioApi.download(url, max_bytes: max_bytes)
      [ data, type.presence || content_type ]
    end
  end
end
