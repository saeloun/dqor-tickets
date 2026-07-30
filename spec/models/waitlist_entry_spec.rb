require "rails_helper"

RSpec.describe WaitlistEntry do
  let(:event) { create(:event) }
  let(:ticket_type) { create(:ticket_type, event:) }

  it "joins the waitlist with a normalized email and generated tokens" do
    entry = event.waitlist_entries.create!(ticket_type:, email: "  ADA@Example.com ", name: "Ada")

    expect(entry.email).to eq("ada@example.com")
    expect(entry).to be_waiting
    expect(entry.offer_token).to be_present
    expect(entry.cancel_token).to be_present
  end

  it "prevents duplicate entries for the same ticket type + email" do
    event.waitlist_entries.create!(ticket_type:, email: "a@b.com")

    expect(event.waitlist_entries.new(ticket_type:, email: "a@b.com")).not_to be_valid
  end

  it "offers a spot with an expiry and detects expiry" do
    entry = event.waitlist_entries.create!(ticket_type:, email: "c@d.com")

    entry.offer!(expires_in: 1.hour)
    expect(entry).to be_offered
    expect(entry.offer_expires_at).to be_within(5.seconds).of(1.hour.from_now)
    expect(entry.offer_expired?).to be(false)

    entry.update!(offer_expires_at: 1.minute.ago)
    expect(entry.offer_expired?).to be(true)
  end

  it "orders waiting entries by position" do
    second = event.waitlist_entries.create!(ticket_type:, email: "s@x.com", position: 2)
    first = event.waitlist_entries.create!(ticket_type:, email: "f@x.com", position: 1)

    expect(event.waitlist_entries.waiting_in_order.to_a).to eq([ first, second ])
  end
end
