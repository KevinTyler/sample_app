module Assistant
  # Photos and videos hosts text to the assistant (e.g. a kid's thank-you video).
  module Media
    MAX_BYTES = ThankYou::MEDIA_MAX_SIZE

    module_function

    def fetch(url, content_type:)
      if url.to_s.start_with?("outbox:")
        # Development simulator: the file was uploaded straight into Active Storage.
        blob = ActiveStorage::Blob.find_signed!(url.delete_prefix("outbox:"))
        return [ blob.download, blob.content_type ]
      end

      data, type = Messaging::TwilioApi.download(url, max_bytes: MAX_BYTES)
      [ data, type.presence || content_type ]
    end
  end
end
