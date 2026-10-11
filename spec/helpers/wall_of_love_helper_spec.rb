require "rails_helper"

RSpec.describe WallOfLoveHelper, type: :helper do
  it "limits native embeds to verified fixed provider URLs and approved modes" do
    x = WallLoveSourceCatalog::SOURCES.find { |source| source.fetch("id") == "S016" }
    youtube = WallLoveSourceCatalog::SOURCES.find { |source| source.fetch("id") == "S064" }
    expect(helper.wall_love_embed_ids(x)).to eq(post_id: "2108067887999336677")
    expect(helper.wall_love_embed_ids(youtube)).to eq(video_id: "a_pj2pci6iE")
    %w[S021 S039].each do |id|
      source = WallLoveSourceCatalog::SOURCES.find { |item| item.fetch("id") == id }
      expect(helper.wall_love_embed_ids(source)).to be_empty
    end
    [ "javascript:alert(1)", "https://x.com.evil.example/user/status/2108067887999336677", "https://user:password@x.com/user/status/2108067887999336677", "http://x.com/user/status/2108067887999336677" ].each do |url|
      expect(helper.wall_love_embed_ids(x.merge("url" => url))).to be_empty
    end
    expect(helper.wall_love_embed_ids(youtube.merge("url" => "https://www.youtube.com.evil.example/watch?v=a_pj2pci6iE"))).to be_empty
    expect(helper.wall_love_embed_ids(youtube.merge("url" => "https://www.youtube.com/watch?v=bad-id"))).to be_empty
  end
end
