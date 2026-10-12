module PagesHelper
  # Unsaved example events for the marketing page previews.
  def sample_event(template = nil)
    Event.new(title: template ? template.name : "Maya turns 30", host_name: "Larkspur", starts_at: Time.zone.parse("2026-11-07 23:30"),
      time_zone: "America/New_York", location_name: "The Greenhouse", status: "published")
  end

  def sample_events
    [
      [ Event.new(title: "Maya turns 30", host_name: "Jordan & Sam", starts_at: Time.zone.parse("2026-11-07 23:30"), time_zone: "America/New_York",
          location_name: "The Greenhouse, Brooklyn", status: "published"),
        InvitationDesign.new(InvitationTemplate.find("confetti-burst").design_defaults) ],
      [ Event.new(title: "Priya & Theo", host_name: "The Rao & Lindqvist families", starts_at: Time.zone.parse("2027-06-12 21:00"), time_zone: "America/Chicago",
          location_name: "Larkfield Gardens", status: "published"),
        InvitationDesign.new(InvitationTemplate.find("garden-arch").design_defaults) ]
    ]
  end
end
