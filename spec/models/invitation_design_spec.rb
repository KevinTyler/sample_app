require "rails_helper"

RSpec.describe InvitationDesign do
  let(:event) { build(:event) }

  it "falls back to the default template" do
    design = described_class.for(event)
    expect(design.template).to eq(InvitationTemplate.default.key)
    expect(design).to be_valid
  end

  it "every built-in template produces a valid design" do
    InvitationTemplate.all.each do |template|
      expect(described_class.new(template.design_defaults)).to be_valid, template.key
    end
  end

  it "rejects values that could inject CSS" do
    design = described_class.for(event)
    design.background_color = "red; } body { display:none"
    design.heading_font = "Comic Sans'; }"
    expect(design).not_to be_valid
    expect(design.css_rule("#card")).to eq("")
  end

  it "rejects text colors too close to the background" do
    design = described_class.for(event)
    design.assign_attributes(background_color: "#FFFFFF", text_color: "#F4F4F4")
    expect(design).not_to be_valid
    expect(design.errors[:text_color]).to be_present
  end

  it "emits CSS custom properties from validated values" do
    css = described_class.for(event).css_rule("#invite-card-1")
    expect(css).to start_with("#invite-card-1 {")
    expect(css).to include("--card-bg: #", "--card-heading-font: '")
  end

  it "switching template resets colors and fonts but keeps the host's message" do
    event.design = { "template" => "garden-arch", "message" => "Dinner at 7", "accent_color" => "#123456" }
    design = described_class.from_params(event, { "template" => "starlit" })
    starlit = InvitationTemplate.find("starlit")
    expect(design.accent_color).to eq(starlit.accent_color)
    expect(design.message).to eq("Dinner at 7")
  end
end
