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

  # Numbers without a country code ("(555) 010-0123", "07700 900123") are taken to be in the given
  # country (calling code, e.g. "1" or "44"); "00…" is the international prefix.
  def with_country(value, country_code)
    phone = normalize(value)
    return phone if phone.nil? || phone.start_with?("+")
    return "+#{phone.delete_prefix('00')}" if phone.start_with?("00") && phone.length > 9

    case country_code.to_s
    when "" then phone
    when "1"
      return "+1#{phone}" if phone.length == 10
      return "+#{phone}" if phone.length == 11 && phone.start_with?("1")

      phone
    else
      phone.start_with?("0") && phone.length >= 9 ? "+#{country_code}#{phone[1..]}" : phone
    end
  end

  def valid?(value)
    value.to_s.match?(FORMAT)
  end
end
