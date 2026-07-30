require "rails_helper"

RSpec.describe "Speakers", type: :request do
  it "shows published speakers and hides drafts" do
    Speaker.create!(name: "Ada Lovelace", title: "The first programmer", published: true)
    Speaker.create!(name: "Draft Speaker Person", published: false)

    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Lovelace")
    expect(response.body).not_to include("Draft Speaker Person")
  end

  it "renders an empty state when none are published" do
    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end
end
