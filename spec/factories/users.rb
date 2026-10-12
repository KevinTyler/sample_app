FactoryBot.define do
  factory :user do
    name { "Jordan Host" }
    sequence(:email_address) { |n| "host#{n}@example.com" }
    password { "correct-horse-battery" }
  end
end
