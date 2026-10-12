# Tiny formatting/parsing helpers for whole-currency amounts stored as integer cents.
module Money
  module_function

  def format(cents, currency)
    symbol = Event::CURRENCIES.fetch(currency.to_s, {})[:symbol] || ""
    amount = (cents.to_i / 100.0)
    "#{symbol}#{amount % 1 == 0 ? amount.to_i : Kernel.format('%.2f', amount)} #{currency.to_s.upcase}".strip
  end

  # "25", "25.5", "$1,250.00" → cents. Returns nil for blank or unparseable input.
  def parse_cents(value)
    cleaned = value.to_s.gsub(/[^\d.]/, "")
    return nil if cleaned.blank? || cleaned.count(".") > 1

    (BigDecimal(cleaned) * 100).round.to_i
  rescue ArgumentError
    nil
  end
end
