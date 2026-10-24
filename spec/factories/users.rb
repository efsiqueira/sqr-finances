# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { "Ada Lovelace" }
    sequence(:username) { |n| "ada_lovelace_#{n}" }
    sequence(:email) { |n| "ada#{n}@sqrfinance.dev" }
    password { "SecretPass123!" }
    password_confirmation { "SecretPass123!" }
  end
end
