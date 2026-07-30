require "rails_helper"

RSpec.describe Talk do
  it "requires a title" do
    expect(Talk.new).not_to be_valid
  end

  it "scopes to published talks" do
    published = Talk.create!(title: "Keynote", published: true)
    Talk.create!(title: "Draft", published: false)

    expect(Talk.published).to contain_exactly(published)
  end

  it "orders scheduled talks with timed ones first" do
    late = Talk.create!(title: "Later", starts_at: Time.utc(2026, 10, 8, 6, 0))
    early = Talk.create!(title: "Earlier", starts_at: Time.utc(2026, 10, 8, 4, 0))
    tba = Talk.create!(title: "TBA", starts_at: nil)

    expect(Talk.scheduled.to_a).to eq([ early, late, tba ])
  end

  it "formats the local time range in the event zone" do
    talk = Talk.create!(title: "Session", starts_at: Time.utc(2026, 10, 8, 4, 0), ends_at: Time.utc(2026, 10, 8, 4, 30))

    expect(talk.time_range).to match(/\d.*(AM|PM).*–.*(AM|PM)/)
    expect(talk.day).to eq(Date.new(2026, 10, 8))
  end
end
