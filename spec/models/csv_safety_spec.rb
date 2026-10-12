require "rails_helper"

RSpec.describe CsvSafety do
  it "neutralizes values that spreadsheets would run as formulas" do
    expect(described_class.row([ "=HYPERLINK(\"http://evil\")", "+1", "-2", "@SUM(A1)", "Dana", 3, nil ]))
      .to eq([ "'=HYPERLINK(\"http://evil\")", "'+1", "'-2", "'@SUM(A1)", "Dana", 3, nil ])
  end
end
