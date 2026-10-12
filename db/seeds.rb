# Demo data for local development: `bin/rails db:seed` (safe to run more than once).
# Sign in as demo@larkspur.test / larkspur-demo-1

return if Rails.env.production?

# Run deliveries synchronously so seeded emails land in the outbox before this process exits.
ActiveJob::Base.queue_adapter = :inline

host = User.find_or_create_by!(email_address: "demo@larkspur.test") do |u|
  u.name = "Jordan Rivera"
  u.password = "larkspur-demo-1"
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
    capacity: 40, default_plus_ones: 1,
    design: InvitationTemplate.find("confetti-burst").design_defaults.merge("message" => "Bring your best dance moves!")
  )
  birthday.save!
  birthday.publish

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

    RsvpSubmission.new(guest: guest, status: status, party_size: party,
      answers: dinner ? { meal.id.to_s => dinner } : {}).save
  end

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
end

puts "Seeded #{User.count} host, #{Event.count} events, #{Guest.count} guests. Sign in: demo@larkspur.test / larkspur-demo-1"
puts "Draft event to publish: #{dinner.title}"
