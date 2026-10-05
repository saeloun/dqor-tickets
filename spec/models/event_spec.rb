require "rails_helper"

RSpec.describe Event, type: :model do
  let(:organization) { Organization.create!(name: "One", slug: "one") }
  let(:event) { organization.events.new(title: "Meetup", slug: "meetup") }

  it "permits incomplete dates only for drafts" do
    expect(event).to be_valid
    event.status = :published
    expect(event).not_to be_valid
    expect(event.errors).to include(:starts_at, :ends_at)
  end

  it "requires a real IANA timezone and strictly increasing dates" do
    event.assign_attributes(timezone: "Not/AZone", starts_at: Time.current, ends_at: Time.current - 1.hour)
    expect(event).not_to be_valid
    expect(event.errors).to include(:timezone, :ends_at)
    event.assign_attributes(timezone: "Asia/Kolkata", ends_at: event.starts_at)
    expect(event).not_to be_valid
    event.ends_at += 1.hour
    expect(event).to be_valid
  end

  it "scopes normalized slugs to the organization" do
    event.save!
    duplicate = organization.events.new(title: "Duplicate", slug: " MEETUP ")
    expect(duplicate).not_to be_valid
    other = Organization.create!(name: "Two", slug: "two")
    duplicate.organization = other
    expect(duplicate).to be_valid
  end
end
