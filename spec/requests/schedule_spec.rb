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
end
