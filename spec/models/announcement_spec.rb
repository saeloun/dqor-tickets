require "rails_helper"

RSpec.describe Announcement do
  it "requires a title" do
    expect(Announcement.new).not_to be_valid
  end

  it "scopes to published and orders the most recent first" do
    older = Announcement.create!(title: "Older", published: true, published_at: 2.days.ago)
    newer = Announcement.create!(title: "Newer", published: true, published_at: 1.hour.ago)
    Announcement.create!(title: "Draft", published: false)

    expect(Announcement.published.recent.to_a).to eq([ newer, older ])
  end
end
