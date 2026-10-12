require "rails_helper"

RSpec.describe WallLoveSourceCatalog do
  it "preserves the curated counts and excludes unverified conference associations from the wall" do
    expect(described_class.main_wall.size).to eq(54)
    expect(described_class.archive.size).to eq(12)
    expect(described_class.related.map { |source| source.fetch("id") }).to match_array(%w[S014 S068])
    expect(described_class::SOURCES.size).to eq(68)
    expect(described_class::SOURCES.map { |source| source.fetch("id") }).not_to include("S069")
    expect(described_class.main_wall.map { |source| source.fetch("id") }).not_to include("S014", "S068")
  end

  it "contains only public presentation facts and string platform IDs" do
    expect(described_class::SOURCES.map { |source| source.fetch("url") }.uniq.size).to eq(68)
    described_class::SOURCES.each do |source|
      expect(source.keys).not_to include("media", "rights", "local_asset_path", "media_ids", "date", "unresolved_source_leads", "evidence_url")
      expect(source.fetch("embed").values_at("status_id", "video_id").compact).to all(be_a(String))
      expect(WallLoveNote.safe_source_url(source.fetch("url"))).to eq(source.fetch("url"))
    end
    expect(described_class::SOURCES.count { |source| source["excerpt"].present? }).to eq(5)
  end

  it "keeps family-style and chat-screenshot sources text only" do
    %w[S021 S039].each do |id|
      source = described_class::SOURCES.find { |record| record.fetch("id") == id }
      expect(source.fetch("embed").fetch("mode")).to eq("linked_card")
    end
  end
end
