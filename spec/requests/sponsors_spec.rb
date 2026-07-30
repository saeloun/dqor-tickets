require "rails_helper"

RSpec.describe "Sponsors", type: :request do
  it "shows published sponsors and hides drafts" do
    Sponsor.create!(name: "Saeloun", tier: "platinum", published: true)
    Sponsor.create!(name: "Secret Draft Sponsor", published: false)

    get sponsors_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Saeloun")
    expect(response.body).not_to include("Secret Draft Sponsor")
  end

  it "renders an empty state when none are published" do
    get sponsors_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end
end
