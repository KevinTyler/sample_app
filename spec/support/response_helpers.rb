module ResponseHelpers
  # The response body with HTML entities decoded, for matching human-readable text.
  def page_text
    CGI.unescapeHTML(response.body)
  end
end

RSpec.configure { |config| config.include ResponseHelpers, type: :request }
