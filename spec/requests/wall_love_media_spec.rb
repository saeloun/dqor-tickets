require "rails_helper"

RSpec.describe "Wall of Love media", type: :request do
  it "renders the full source collection, four visible recordings and honest archive labels without JavaScript" do
    get wall_of_love_path
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.css(".wall-love-collection [data-source-id]").size).to eq(54)
    expect(page.css("[data-recording-source-id]").size).to eq(4)
    expect(page.css("[data-archive-source-id]").size).to eq(14)
    expect(page.css(".wall-love-collection [data-source-id][hidden]")).to be_empty
    expect(page.css("iframe")).to be_empty
    expect(response.body).to include("Before the gathering", "Related technical context", "not conference testimonials", "Summary:")
    expect(page.css('[data-source-id="S021"] button, [data-source-id="S039"] button')).to be_empty
    expect(response.body).not_to include("2108980145210163442", "local_asset_path", "libfile_", "pbs.twimg.com", "DQOR_organizer_opening_42sec.mp4", "retained from the earlier collection", "No local video file collected", "chat not inspected")
  end

  it "links each curated source to its exact canonical original and includes platform-only recording previews" do
    get wall_of_love_path
    page = Nokogiri::HTML(response.body)
    WallLoveSourceCatalog.main_wall.each do |source|
      card = page.at_css(".wall-love-collection [data-source-id='#{source.fetch('id')}']")
      expect(card.at_css("a")['href']).to eq(source.fetch("url"))
      expect(card.text).to include(source.fetch("author"), source.fetch("caption"))
    end
    previews = page.css(".wall-love-recordings img")
    expect(previews.size).to eq(4)
    expect(previews.map { |image| image['src'] }).to all(start_with("https://i.ytimg.com/vi/"))
  end
end
