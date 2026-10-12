# Light-touch phone normalization. We keep a leading "+" (E.164 style) and digits only.
# Full validation/formatting per country belongs to the SMS provider integration.
module PhoneNumber
  FORMAT = /\A\+?[0-9]{7,15}\z/

  module_function

  def normalize(value)
    return nil if value.blank?

    raw = value.to_s.strip
    digits = raw.gsub(/\D/, "")
    return nil if digits.empty?

    raw.start_with?("+") ? "+#{digits}" : digits
  end

  def valid?(value)
    value.to_s.match?(FORMAT)
  end
end
