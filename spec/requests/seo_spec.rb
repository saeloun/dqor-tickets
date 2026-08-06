require "rails_helper"

RSpec.describe "SEO & AEO", type: :request do
  it "serves robots.txt that allows crawling, blocks private paths, and points to the sitemap" do
    get "/robots.txt"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("User-agent: *")
    expect(response.body).to include("Disallow: /avo")
    expect(response.body).to include("Disallow: /account")
    expect(response.body).to match(%r{Sitemap: https?://[^/\s]+/sitemap\.xml})
  end

  it "serves a sitemap of public pages, including announced speakers and published info pages" do
    speaker = Speaker.create!(name: "Ada Lovelace", published: true, status: :announced)
    Speaker.create!(name: "Draft Person", published: false)
    page = InfoPage.create!(title: "Travel", slug: "travel", published: true)

    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to include(tickets_store_path)
    expect(response.body).to include(speaker_path(speaker))
    expect(response.body).to include(info_page_path(page))
    expect(response.body).not_to include("Draft")
  end

  it "serves an llms.txt describing the conference for answer engines" do
    get "/llms.txt"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("# Deccan Queen on Rails 2026")
    expect(response.body).to include("/tickets")
  end

  it "emits a canonical link and Event JSON-LD on the home page" do
    create(:ticket_type, name: "Conference Pass", price_paise: 350_000)
    Speaker.create!(name: "Grace Hopper", published: true, status: :announced)

    get root_path

    expect(response.body).to include(%(<link rel="canonical" href="http://www.example.com/">))
    json = response.body[%r{<script type="application/ld\+json">(.+?)</script>}m, 1]
    expect(json).to be_present
    data = JSON.parse(json)
    expect(data["@type"]).to eq("Event")
    expect(data["startDate"]).to eq("2026-10-08")
    expect(data["location"]["name"]).to eq("Hyatt Regency Pune")
    expect(data["offers"]).to include(a_hash_including("priceCurrency" => "INR", "name" => "Conference Pass"))
    expect(data["performer"]).to include(a_hash_including("name" => "Grace Hopper"))
  end
end
