FactoryBot.define do
  factory :event do
    owner factory: :user
    title { "Maya's Birthday" }
    time_zone { "America/New_York" }
    starts_at { 3.weeks.from_now.change(hour: 23, min: 0) }
    location_name { "The Greenhouse" }
    address { "12 Garden Street, Brooklyn" }

    trait :published do
      status { "published" }
      published_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { Time.current }
    end
  end

  factory :guest do
    event
    sequence(:name) { |n| "Guest #{n}" }
    sequence(:email) { |n| "guest#{n}@example.com" }
  end

  factory :event_question do
    event
    prompt { "Dinner choice?" }
    kind { "choice" }
    options { [ "Chicken", "Risotto" ] }
  end
end
