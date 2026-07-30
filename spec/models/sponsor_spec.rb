require "rails_helper"

RSpec.describe Sponsor do
  it "requires a name" do
    expect(Sponsor.new).not_to be_valid
  end

  it "validates tier when present" do
    expect(Sponsor.new(name: "Acme", tier: "bogus")).not_to be_valid
    expect(Sponsor.new(name: "Acme", tier: "gold")).to be_valid
    expect(Sponsor.new(name: "Acme", tier: nil)).to be_valid
  end

  it "scopes to published and defaults the tier label" do
    shown = Sponsor.create!(name: "Shown", published: true)
    Sponsor.create!(name: "Hidden", published: false)

    expect(Sponsor.published).to contain_exactly(shown)
    expect(shown.tier_label).to eq("community")
  end
end
