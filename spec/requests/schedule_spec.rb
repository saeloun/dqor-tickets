require "rails_helper"

RSpec.describe "Schedule", type: :request do
  it "shows published talks and hides drafts" do
    Talk.create!(title: "Rails at Scale", speaker_name: "Ada", published: true, starts_at: Time.utc(2026, 10, 8, 4, 0))
    Talk.create!(title: "Secret Draft Talk", published: false)

    get schedule_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rails at Scale")
    expect(response.body).not_to include("Secret Draft Talk")
  end

  it "renders an empty state when nothing is published" do
    get schedule_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("being finalised")
  end

  [ :root_path, :tickets_store_path ].each do |page_path|
    it "links every Schedule navigation entry to the full agenda from #{page_path}" do
      get public_send(page_path)

      links = response.parsed_body.css("#nav-links a, #nav-mobile-menu a, footer a").select { |link| link.text == "Schedule" }
      expect(links.size).to eq(3)
      expect(links.map { |link| link["href"] }).to eq([ schedule_path ] * 3)
      expect(links.first["data-section"]).to be_nil
      expect(links.first["class"].split).not_to include("active")
    end
  end

  it "marks the desktop Schedule link active on the full agenda" do
    get schedule_path

    link = response.parsed_body.at_css("#nav-links a[href='#{schedule_path}']")
    expect(link["class"].split).to include("active")
    expect(link["data-section"]).to be_nil
  end
end
