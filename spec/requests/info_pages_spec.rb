require "rails_helper"

RSpec.describe "Info pages", type: :request do
  it "lists and shows published pages, hiding drafts" do
    InfoPage.create!(title: "Venue & travel", slug: "venue", body: "Hyatt Regency, Pune.", published: true)
    InfoPage.create!(title: "Draft Info Page", slug: "draft", published: false)

    get info_pages_path
    expect(response.body).to include("Venue &amp; travel")
    expect(response.body).not_to include("Draft Info Page")

    get info_page_path("venue")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hyatt Regency, Pune.")
  end

  it "renders an empty state when there are none" do
    get info_pages_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end
end
