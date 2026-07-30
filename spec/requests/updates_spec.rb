require "rails_helper"

RSpec.describe "Updates", type: :request do
  it "shows published announcements and hides drafts" do
    Announcement.create!(title: "Doors open at 9am", published: true, published_at: Time.current)
    Announcement.create!(title: "Secret Draft Update", published: false)

    get updates_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Doors open at 9am")
    expect(response.body).not_to include("Secret Draft Update")
  end

  it "renders an empty state when there are none" do
    get updates_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No updates yet")
  end
end
