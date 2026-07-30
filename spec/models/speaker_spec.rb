require "rails_helper"

RSpec.describe Speaker do
  it "requires a name" do
    expect(Speaker.new).not_to be_valid
  end

  it "scopes to published speakers" do
    shown = Speaker.create!(name: "Ada", published: true)
    Speaker.create!(name: "Hidden", published: false)

    expect(Speaker.published).to contain_exactly(shown)
  end

  it "builds social URLs from handles" do
    speaker = Speaker.new(name: "Ada", twitter: "@ada", github: "ada")

    expect(speaker.twitter_url).to eq("https://twitter.com/ada")
    expect(speaker.github_url).to eq("https://github.com/ada")
  end
end
