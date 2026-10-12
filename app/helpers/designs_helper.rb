module DesignsHelper
  # Original color palette suggestions offered in the design editor.
  PALETTES = [
    { name: "Blush & Plum", bg: "#FDF2F4", ink: "#4A2040", accent: "#D46A8C" },
    { name: "Sea Glass", bg: "#EEF6F4", ink: "#1F3D3A", accent: "#3F9C8F" },
    { name: "Midnight Gold", bg: "#111827", ink: "#F6EBD4", accent: "#D9A93F" },
    { name: "Sunflower", bg: "#FFF8DC", ink: "#3B2F14", accent: "#D99A00" },
    { name: "Lavender Haze", bg: "#F4F1FB", ink: "#2F2A4A", accent: "#8C7AE6" },
    { name: "Terracotta", bg: "#FBF1EA", ink: "#4A2A1E", accent: "#C8653C" },
    { name: "Evergreen", bg: "#1E3A2F", ink: "#F1EFE6", accent: "#C9B37E" },
    { name: "Paper & Ink", bg: "#FFFFFF", ink: "#1B1B1F", accent: "#1B1B1F" }
  ].freeze

  def design_editor_templates_json
    InvitationTemplate.all.to_h { |t| [ t.key, t.design_defaults.merge("artwork" => t.artwork) ] }.to_json
  end

  def design_editor_fonts_json
    InvitationDesign::FONTS.transform_values(&:stack).to_json
  end

  def font_options(selected)
    grouped = InvitationDesign::FONTS.values.group_by(&:category).transform_values { |fonts| fonts.map { |f| [ f.name, f.key ] } }
    grouped_options_for_select(grouped, selected)
  end

  # Tiny diagram for each layout choice, drawn with SVG presentation attributes (CSP-safe).
  def layout_diagram(layout)
    lines = case layout
    when "left" then [ [ 8, 30, 22 ], [ 8, 36, 28 ], [ 8, 42, 16 ] ]
    when "split" then [ [ 26, 18, 14 ], [ 26, 24, 16 ], [ 26, 30, 10 ] ]
    else [ [ 11, 22, 22 ], [ 8, 28, 28 ], [ 14, 34, 16 ] ]
    end
    tag.svg(viewBox: "0 0 44 52", class: "layout-diagram", aria: { hidden: true }) do
      safe_join([
        tag.rect(x: 1, y: 1, width: 42, height: 50, rx: 3, fill: "#fff", stroke: "#d3ccbf"),
        (tag.rect(x: 5, y: 5, width: 34, height: 42, fill: "none", stroke: "#5458d1", "stroke-width": 1.2) if layout == "framed"),
        (tag.rect(x: 5, y: 8, width: 17, height: 36, rx: 2, fill: "#ececfc") if layout == "split"),
        *lines.map { |x, y, w| tag.rect(x: x, y: y, width: w, height: 3, rx: 1.5, fill: "#5a5d80") }
      ].compact)
    end
  end

  def palette_swatch(palette)
    tag.svg(viewBox: "0 0 48 24", class: "palette-swatch", aria: { hidden: true }) do
      safe_join([
        tag.rect(width: 48, height: 24, rx: 6, fill: palette[:bg], stroke: "#d3ccbf"),
        tag.circle(cx: 17, cy: 12, r: 6, fill: palette[:ink]),
        tag.circle(cx: 31, cy: 12, r: 6, fill: palette[:accent])
      ])
    end
  end
end
