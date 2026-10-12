# Larkspur's original invitation templates. Each template is a starting point: colors, fonts,
# layout, wording and an SVG artwork partial (app/views/invitation_artworks/_<artwork>.html.erb)
# drawn for this app. Hosts can change everything afterwards in the design editor.
InvitationTemplate = Data.define(:key, :name, :occasion, :background_color, :text_color, :accent_color,
  :heading_font, :body_font, :layout, :artwork, :headline, :tagline) do
  def self.all
    self::REGISTRY
  end

  def self.find(key)
    self::REGISTRY.find { |t| t.key == key.to_s }
  end

  def self.default
    self::REGISTRY.first
  end

  def self.occasions
    self::REGISTRY.map(&:occasion).uniq
  end

  def design_defaults
    {
      "template" => key, "background_color" => background_color, "text_color" => text_color,
      "accent_color" => accent_color, "heading_font" => heading_font, "body_font" => body_font,
      "layout" => layout, "headline" => headline, "tagline" => tagline, "show_artwork" => artwork.present?
    }
  end
end

InvitationTemplate::REGISTRY = [
  InvitationTemplate.new(key: "garden-arch", name: "Garden Arch", occasion: "Wedding & showers",
    background_color: "#FBF6EE", text_color: "#33402F", accent_color: "#7A9E7E",
    heading_font: "cormorant-garamond", body_font: "lora", layout: "centered", artwork: "garden_arch",
    headline: "Together with their families", tagline: "Please join us"),
  InvitationTemplate.new(key: "confetti-burst", name: "Confetti Burst", occasion: "Birthday",
    background_color: "#FFF8F0", text_color: "#2D2A4A", accent_color: "#FF6B6B",
    heading_font: "abril-fatface", body_font: "dm-sans", layout: "centered", artwork: "confetti",
    headline: "Let's celebrate!", tagline: "You're invited"),
  InvitationTemplate.new(key: "deco-fan", name: "Gilded Fan", occasion: "Cocktails & galas",
    background_color: "#14213D", text_color: "#F5E6C8", accent_color: "#D4A845",
    heading_font: "playfair-display", body_font: "josefin-sans", layout: "framed", artwork: "deco_fan",
    headline: "An evening to remember", tagline: "The pleasure of your company is requested"),
  InvitationTemplate.new(key: "starlit", name: "Starlit", occasion: "Evening & holidays",
    background_color: "#1B1F3B", text_color: "#EEF0FF", accent_color: "#A8B4FF",
    heading_font: "fraunces", body_font: "dm-sans", layout: "centered", artwork: "starlit",
    headline: "A night under the stars", tagline: "Join us"),
  InvitationTemplate.new(key: "citrus-picnic", name: "Citrus Picnic", occasion: "Summer & casual",
    background_color: "#FFFBEA", text_color: "#3A3A2A", accent_color: "#F2A541",
    heading_font: "caveat", body_font: "montserrat", layout: "left", artwork: "citrus",
    headline: "Come hang out!", tagline: "Good food, good friends"),
  InvitationTemplate.new(key: "gallery", name: "Gallery", occasion: "Work & minimal",
    background_color: "#FFFFFF", text_color: "#16161D", accent_color: "#5B5BD6",
    heading_font: "montserrat", body_font: "dm-sans", layout: "left", artwork: "gallery",
    headline: "You're invited", tagline: "Save the date"),
  InvitationTemplate.new(key: "watercolor", name: "Watercolor Bloom", occasion: "Baby & bridal showers",
    background_color: "#FDFBFF", text_color: "#4A3F5C", accent_color: "#C9A7E0",
    heading_font: "great-vibes", body_font: "lora", layout: "centered", artwork: "watercolor",
    headline: "Oh, happy day", tagline: "Please join us for a shower"),
  InvitationTemplate.new(key: "winter-pines", name: "Winter Pines", occasion: "Evening & holidays",
    background_color: "#F4F7F5", text_color: "#1F3B2D", accent_color: "#B23A48",
    heading_font: "fraunces", body_font: "lora", layout: "centered", artwork: "winter_pines",
    headline: "Season's greetings", tagline: "Come in from the cold"),
  InvitationTemplate.new(key: "retro-sunset", name: "Retro Sunset", occasion: "Birthday",
    background_color: "#FFF3E2", text_color: "#3B1F2B", accent_color: "#E4572E",
    heading_font: "abril-fatface", body_font: "montserrat", layout: "centered", artwork: "retro_sunset",
    headline: "Good times ahead", tagline: "You're invited"),
  InvitationTemplate.new(key: "plain-paper", name: "Plain Paper", occasion: "Upload your own",
    background_color: "#FFFFFF", text_color: "#222222", accent_color: "#6B6FD8",
    heading_font: "fraunces", body_font: "dm-sans", layout: "centered", artwork: nil,
    headline: "You're invited", tagline: nil)
].freeze
