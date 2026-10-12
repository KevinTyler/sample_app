# Spreadsheet apps execute cells that start with =, +, -, @ (and tab/CR variants) as formulas.
# Guest-supplied values (names, notes, answers) are exported through this guard so a guest can't
# plant a formula in the host's spreadsheet ("CSV injection").
module CsvSafety
  TRIGGERS = /\A[=+\-@\t\r]/

  module_function

  def cell(value)
    return value unless value.is_a?(String)

    value.match?(TRIGGERS) ? "'#{value}" : value
  end

  def row(values)
    values.map { |v| cell(v) }
  end
end
