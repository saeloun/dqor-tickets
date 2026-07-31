require "rails_helper"

RSpec.describe InfoPage do
  it "requires a title and a valid, unique slug" do
    InfoPage.create!(title: "Venue", slug: "venue")

    expect(InfoPage.new(title: "Another", slug: "venue")).not_to be_valid
    expect(InfoPage.new(title: "Bad", slug: "Not A Slug!")).not_to be_valid
    expect(InfoPage.new(title: "Travel", slug: "travel")).to be_valid
  end

  it "normalizes the slug and uses it as the param" do
    page = InfoPage.create!(title: "Venue", slug: "  VENUE ")

    expect(page.slug).to eq("venue")
    expect(page.to_param).to eq("venue")
  end
end
