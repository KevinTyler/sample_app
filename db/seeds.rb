# Demo data for local development: `bin/rails db:seed` (safe to run more than once).
# Sign in as demo@cordially.test / cordially-demo-1

return if Rails.env.production?

# Run deliveries synchronously so seeded emails land in the outbox before this process exits.
ActiveJob::Base.queue_adapter = :inline

host = User.find_or_create_by!(email_address: "demo@cordially.test") do |u|
  u.name = "Jordan Rivera"
  u.password = "cordially-demo-1"
end

birthday = host.owned_events.find_or_initialize_by(title: "Maya's 30th Birthday")
if birthday.new_record?
  birthday.assign_attributes(
    host_name: "Jordan & Sam", time_zone: "America/New_York",
    starts_at: 3.weeks.from_now.in_time_zone("America/New_York").change(hour: 19, min: 30),
    ends_at: 3.weeks.from_now.in_time_zone("America/New_York").change(hour: 23, min: 0),
    rsvp_deadline: 2.weeks.from_now.in_time_zone("America/New_York").change(hour: 23, min: 59),
    location_name: "The Greenhouse", address: "12 Garden Street, Brooklyn, NY",
    description: "Dinner, cake and dancing. Dress code: garden party.\nStreet parking is easiest after 7pm.",
    capacity: 40, default_plus_ones: 1, track_kids: true, ask_plus_one_names: true, auto_nudge: true, auto_day_before: true,
    design: InvitationTemplate.find("confetti-burst").design_defaults.merge("message" => "Bring your best dance moves!",
      "envelope" => "berry", "liner" => "stripe", "stamp" => "heart")
  )
  birthday.save!
  birthday.publish

  birthday.links.create!(url: "https://www.opentable.com/r/the-greenhouse-brooklyn")
  birthday.links.create!(url: "https://open.spotify.com/playlist/example", label: "Add a song to the playlist")
  birthday.links.create!(url: "https://www.amazon.com/registries/example")

  meal = birthday.questions.create!(prompt: "Dinner choice", kind: "choice", options: [ "Roast chicken", "Mushroom risotto", "Kids' pasta" ], required: true)
  birthday.questions.create!(prompt: "Any allergies we should know about?", kind: "short_text")

  [
    [ "Dana Whitfield", "dana@example.com", "Family", 1, "yes", 2, "Mushroom risotto" ],
    [ "Lee Park", "lee@example.com", "Work", 0, "yes", 1, "Roast chicken" ],
    [ "Priya Shah", "priya@example.com", "College", 1, "maybe", 2, "Roast chicken" ],
    [ "Theo Lindqvist", "theo@example.com", "College", 0, "no", 0, nil ],
    [ "Sam & Alex Moreno", "moreno@example.com", "Family", 2, "pending", 0, nil ],
    [ "Grandma Rose", nil, "Family", 0, "pending", 0, nil ]
  ].each do |name, email, group, plus, status, party, dinner|
    guest = birthday.guests.create!(name: name, email: email, group_name: group, plus_ones_allowed: plus)
    next if status == "pending"

    RsvpSubmission.new(guest: guest, status: status, adults: [ party, 1 ].max, kids: 0,
      answers: dinner ? { meal.id.to_s => dinner } : {}).save
  end

  birthday.guestbook_entries.create!(guest: birthday.guests.find_by(name: "Lee Park"), author_name: "Lee Park",
    body: "Thirty looks good on you. Saving a dance!")

  # Send the invitations for real (into the dev outbox at /dev/outbox), leaving one guest uninvited
  # so the "Send invitations" panel has something to do.
  invitation = birthday.messages.create!(kind: "invitation", author: host, channels: %w[email],
    idempotency_key: "seed-invitations", audience: { "guest_ids" => birthday.guests.where.not(name: "Sam & Alex Moreno").ids })
  invitation.dispatch!
end

dinner = host.owned_events.find_or_create_by!(title: "Autumn Supper Club") do |e|
  e.host_name = "Jordan Rivera"
  e.time_zone = "America/Chicago"
  e.starts_at = 6.weeks.from_now.in_time_zone("America/Chicago").change(hour: 18, min: 0)
  e.location_name = "Our place"
  e.design = InvitationTemplate.find("garden-arch").design_defaults.merge("headline" => "A long table, good friends")
  e.ticket_price = "45" if Payments.enabled? # a ticketed event (test checkout in development)
end

# A party that already happened, ready for thank-yous.
party = host.owned_events.find_or_initialize_by(title: "Jonah's 5th Birthday")
if party.new_record?
  party.assign_attributes(host_name: "The Riveras", time_zone: "America/New_York", location_name: "Lakeside Park pavilion",
    starts_at: 2.days.ago.in_time_zone("America/New_York").change(hour: 14), track_kids: true,
    design: InvitationTemplate.find("balloon-bunch").design_defaults.merge("envelope" => "sky", "liner" => "confetti", "stamp" => "star"))
  party.status = "published"
  party.published_at = 3.weeks.ago
  party.save!(validate: false)
  guests = [
    [ "Dana Whitfield", "dana@example.com", "+15550100", "Dinosaur Lego set" ],
    [ "Grandma Rose", nil, "+15550101", "Picture books" ],
    [ "The Morenos", "moreno@example.com", nil, "Art easel" ],
    [ "Lee Park", "lee@example.com", "+15550111", "Soccer ball" ]
  ].map do |name, email, phone, gift|
    guest = party.guests.create!(name: name, email: email, phone: phone, rsvp_status: "yes", party_size: 2, kids_count: 1)
    party.gifts.create!(guest: guest, description: gift)
    guest
  end
  party.thank_yous.create!(gift: party.gifts.find_by(description: "Picture books"), guest: guests[1],
    message: "Thank you for the books Grandma! We read the dragon one three times.", signed: "Love, Jonah")
end

puts "Seeded #{User.count} host, #{Event.count} events, #{Guest.count} guests. Sign in: demo@cordially.test / cordially-demo-1"
puts "Draft event to publish: #{dinner.title}"
