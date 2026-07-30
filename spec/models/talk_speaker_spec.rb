require "rails_helper"

RSpec.describe "Talk and Speaker linking" do
  it "prefers the linked speaker's name over the typed one" do
    speaker = Speaker.create!(name: "Ada Lovelace")
    talk = Talk.create!(title: "Analytical Engines", speaker_name: "Typed Name", speaker: speaker)

    expect(talk.speaker_display).to eq("Ada Lovelace")
  end

  it "falls back to the typed speaker name when unlinked" do
    expect(Talk.create!(title: "T", speaker_name: "Typed Name").speaker_display).to eq("Typed Name")
  end

  it "exposes a speaker's published talks" do
    speaker = Speaker.create!(name: "Ada")
    published = Talk.create!(title: "Pub", speaker: speaker, published: true)
    Talk.create!(title: "Draft", speaker: speaker, published: false)

    expect(speaker.published_talks).to contain_exactly(published)
  end
end
