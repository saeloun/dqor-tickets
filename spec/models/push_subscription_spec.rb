require "rails_helper"

RSpec.describe PushSubscription do
  it "requires an endpoint and keys" do
    expect(PushSubscription.new).not_to be_valid
  end

  it "enforces endpoint uniqueness" do
    PushSubscription.create!(endpoint: "https://push.example/1", p256dh_key: "p", auth_key: "a")
    duplicate = PushSubscription.new(endpoint: "https://push.example/1", p256dh_key: "p", auth_key: "a")

    expect(duplicate).not_to be_valid
  end

  it "normalizes the email" do
    subscription = PushSubscription.create!(endpoint: "https://push.example/2", p256dh_key: "p", auth_key: "a", email: "  Grace@Example.COM ")

    expect(subscription.email).to eq("grace@example.com")
  end
end
