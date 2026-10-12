# Personal RSVP links carry their secret in the URL path (/i/<token>), which Rails' parameter
# filtering doesn't cover in "Started GET ..." lines. Scrub those tokens from every log line.
module TokenScrubbingFormatter
  PATTERN = %r{(/i/)[A-Za-z0-9_-]{20,}}

  def call(severity, time, progname, msg)
    msg = msg.gsub(PATTERN, '\1[FILTERED]') if msg.is_a?(String)
    super
  end
end

Rails.application.config.after_initialize do
  loggers = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts : [ Rails.logger ]
  loggers.each { |logger| logger.formatter&.extend(TokenScrubbingFormatter) }
end
