module PagesHelper
  # Unsaved example events for the marketing page previews.
  def sample_event(template = nil, title: nil)
    Event.new(title: title || (template ? template.name : "Maya turns 30"), host_name: "Jordan & Sam", starts_at: Time.zone.parse("2026-11-07 23:30"),
      time_zone: "America/New_York", location_name: "The Greenhouse, Brooklyn", status: "published")
  end

  def sample_design(key, **overrides)
    InvitationDesign.new(InvitationTemplate.find(key).design_defaults.merge(overrides.stringify_keys))
  end

  # [css class, event, design] for the three cards fanned out in the landing hero.
  def hero_cards
    [
      [ "mk-stage__back-left", Event.new(title: "A long table", host_name: "The Thursday Supper Club", starts_at: Time.zone.parse("2026-10-16 23:00"),
          time_zone: "America/New_York", location_name: "Ferro's back room", status: "published"),
        sample_design("starlit", tagline: "Supper club", headline: "Friday · 7 PM") ],
      [ "mk-stage__back-right", Event.new(title: "A shower for Priya", host_name: "Her sisters", starts_at: Time.zone.parse("2026-09-20 18:00"),
          time_zone: "America/Chicago", location_name: "Larkfield Gardens", status: "published"),
        sample_design("watercolor", headline: "Oh, baby") ],
      [ "mk-stage__front", Event.new(title: "Maya turns thirty", host_name: "Jordan & Sam", starts_at: Time.zone.parse("2026-11-08 00:30"),
          time_zone: "America/New_York", location_name: "The Greenhouse, Brooklyn", status: "published"),
        sample_design("garden-arch", tagline: "Please join us to celebrate", headline: nil) ]
    ]
  end

  # [template key, title, overrides] for the design gallery.
  GALLERY = [
    [ "garden-arch", "Priya & Theo", { headline: "Together with their families" } ],
    [ "deco-fan", "Black Tie New Year's Eve", { headline: "An evening to remember" } ],
    [ "confetti-burst", "Jonah is five!", { headline: "Let's celebrate" } ],
    [ "winter-pines", "Winter Supper", { headline: "Come in from the cold", tagline: nil } ],
    [ "citrus-picnic", "Picnic in the park", {} ],
    [ "retro-sunset", "Dad's 60th", {} ],
    [ "gallery", "Studio opening", { tagline: "Save the date" } ],
    [ "watercolor", "Baby Rao", { headline: "Oh, happy day" } ]
  ].freeze
end
