# The look of an event's invitation: a template plus the host's customizations, stored in
# events.design (JSON). Every value that ends up in CSS is validated here (hex colors, fonts and
# layouts from fixed lists), which is what makes it safe to emit as a nonced <style> block.
class InvitationDesign
  include ActiveModel::Model
  include ActiveModel::Attributes

  Font = Data.define(:key, :name, :stack, :category)

  FONTS = [
    Font.new("fraunces", "Fraunces", "'Fraunces', Georgia, serif", "Serif"),
    Font.new("playfair-display", "Playfair Display", "'Playfair Display', Georgia, serif", "Serif"),
    Font.new("cormorant-garamond", "Cormorant Garamond", "'Cormorant Garamond', Garamond, Georgia, serif", "Serif"),
    Font.new("lora", "Lora", "'Lora', Georgia, serif", "Serif"),
    Font.new("abril-fatface", "Abril Fatface", "'Abril Fatface', Georgia, serif", "Display"),
    Font.new("great-vibes", "Great Vibes", "'Great Vibes', 'Brush Script MT', cursive", "Script"),
    Font.new("caveat", "Caveat", "'Caveat', 'Comic Sans MS', cursive", "Handwritten"),
    Font.new("montserrat", "Montserrat", "'Montserrat', 'Helvetica Neue', Arial, sans-serif", "Sans serif"),
    Font.new("josefin-sans", "Josefin Sans", "'Josefin Sans', 'Helvetica Neue', Arial, sans-serif", "Sans serif"),
    Font.new("dm-sans", "DM Sans", "'DM Sans', 'Helvetica Neue', Arial, sans-serif", "Sans serif")
  ].index_by(&:key).freeze

  LAYOUTS = {
    "centered" => "Centered",
    "left" => "Left aligned",
    "framed" => "Framed border",
    "split" => "Side by side"
  }.freeze

  PHOTO_STYLES = {
    "banner" => "Banner above the text",
    "background" => "Full background",
    "inset" => "Round inset"
  }.freeze

  HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/
  TEXT_LIMITS = { headline: 80, tagline: 120, message: 600 }.freeze

  attribute :template, :string
  attribute :background_color, :string
  attribute :text_color, :string
  attribute :accent_color, :string
  attribute :heading_font, :string
  attribute :body_font, :string
  attribute :layout, :string
  attribute :headline, :string
  attribute :tagline, :string
  attribute :message, :string
  attribute :show_artwork, :boolean
  attribute :photo_style, :string, default: "banner"

  validates :template, inclusion: { in: ->(_) { InvitationTemplate.all.map(&:key) } }
  validates :background_color, :text_color, :accent_color, format: { with: HEX_COLOR, message: "must be a color like #A1B2C3" }
  validates :heading_font, :body_font, inclusion: { in: FONTS.keys }
  validates :layout, inclusion: { in: LAYOUTS.keys }
  validates :photo_style, inclusion: { in: PHOTO_STYLES.keys }
  validates :headline, length: { maximum: TEXT_LIMITS[:headline] }
  validates :tagline, length: { maximum: TEXT_LIMITS[:tagline] }
  validates :message, length: { maximum: TEXT_LIMITS[:message] }
  validate :readable_contrast

  # Builds the design for an event: template defaults, overlaid with the host's saved choices.
  def self.for(event)
    stored = (event.design || {}).to_h.stringify_keys
    template = InvitationTemplate.find(stored["template"]) || InvitationTemplate.default
    new(template.design_defaults.merge(stored.slice(*attribute_names)))
  end

  # Applies submitted editor values. Switching templates resets to that template's defaults
  # unless the form also sent explicit values.
  def self.from_params(event, params)
    params = params.to_h.stringify_keys.slice(*attribute_names)
    current = self.for(event)
    base = if params["template"].present? && params["template"] != current.template && (tpl = InvitationTemplate.find(params["template"]))
      tpl.design_defaults.merge("message" => current.message, "photo_style" => current.photo_style)
    else
      current.attributes
    end
    new(base.merge(params.compact_blank.merge(params.slice("headline", "tagline", "message"))))
  end

  def template_record
    InvitationTemplate.find(template) || InvitationTemplate.default
  end

  def artwork
    template_record.artwork if show_artwork
  end

  def heading_font_record
    FONTS.fetch(heading_font, FONTS["fraunces"])
  end

  def body_font_record
    FONTS.fetch(body_font, FONTS["dm-sans"])
  end

  def css_variables
    {
      "--card-bg" => background_color,
      "--card-ink" => text_color,
      "--card-accent" => accent_color,
      "--card-heading-font" => heading_font_record.stack,
      "--card-body-font" => body_font_record.stack
    }
  end

  # Safe because every value is validated (colors) or comes from FONTS (font stacks).
  def css_rule(selector)
    return "" unless valid?

    declarations = css_variables.map { |name, value| "#{name}: #{value};" }.join(" ")
    "#{selector} { #{declarations} }"
  end

  def to_storage
    attributes.compact
  end

  private
    def readable_contrast
      return unless [ background_color, text_color ].all? { |c| c.to_s.match?(HEX_COLOR) }

      if self.class.contrast_ratio(background_color, text_color) < 3.0
        errors.add(:text_color, "is too close to the background color to read comfortably")
      end
    end

    class << self
      # WCAG relative-luminance contrast ratio between two hex colors.
      def contrast_ratio(a, b)
        la, lb = luminance(a), luminance(b)
        (([ la, lb ].max + 0.05) / ([ la, lb ].min + 0.05)).round(2)
      end

      def luminance(hex)
        r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
        channel = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
        0.2126 * channel.(r) + 0.7152 * channel.(g) + 0.0722 * channel.(b)
      end
    end
end
