require "rails_helper"

RSpec.describe "Sponsorship" do
  let(:event) { create(:event) }

  it "creates tiers, sponsors and sponsor orders scoped to an event" do
    tier = event.sponsorship_tiers.create!(name: "Platinum", level: 1, price_minor: 5_000_000, currency: "INR", benefits: { "comp_tickets" => 4 })
    sponsor = event.sponsors.create!(name: "Acme Corp", sponsorship_tier: tier, entity_type: "body_corporate")
    order = sponsor.sponsor_orders.create!(sponsorship_tier: tier, amount_minor: 5_000_000, currency: "INR", status: "invoiced")

    expect(sponsor.slug).to eq("acme-corp")
    expect(sponsor).to be_body_corporate
    expect(tier.sponsors).to include(sponsor)
    expect(order).to be_invoiced
    expect(event.sponsors).to include(sponsor)
  end

  it "auto-generates a unique sponsor slug per event" do
    event.sponsors.create!(name: "Acme")

    dup = event.sponsors.new(name: "Acme")
    expect(dup).not_to be_valid
    expect(dup.errors[:slug]).to be_present
  end

  it "orders tiers by level then position" do
    gold = event.sponsorship_tiers.create!(name: "Gold", level: 2)
    plat = event.sponsorship_tiers.create!(name: "Platinum", level: 1)

    expect(event.sponsorship_tiers.ordered.to_a).to eq([ plat, gold ])
  end

  it "rejects a negative sponsor-order amount" do
    sponsor = event.sponsors.create!(name: "Beta")

    expect(sponsor.sponsor_orders.new(amount_minor: -1)).not_to be_valid
  end
end
