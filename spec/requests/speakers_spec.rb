require "rails_helper"

RSpec.describe "Speakers", type: :request do
  it "shows announced speakers and hides drafts, unpublished, and non-announced" do
    Speaker.create!(name: "Ada Lovelace", title: "The first programmer", published: true, status: :announced)
    Speaker.create!(name: "Draft Speaker Person", published: false)
    Speaker.create!(name: "Pending Yet Public Person", published: true, status: :pending)
    Speaker.create!(name: "Announced Unpublished Person", published: false, status: :announced)

    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Lovelace")
    expect(response.body).not_to include("Draft Speaker Person")
    expect(response.body).not_to include("Pending Yet Public Person")
    expect(response.body).not_to include("Announced Unpublished Person")
  end

  it "renders an empty state when none are announced" do
    get speakers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("coming soon")
  end

  it "shows an announced speaker profile with their talks" do
    speaker = Speaker.create!(name: "Ada Lovelace", title: "Programmer", bio: "The first programmer.", published: true, status: :announced)
    Talk.create!(title: "Analytical Engines", speaker: speaker, published: true)

    get speaker_path(speaker)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada Lovelace")
    expect(response.body).to include("Analytical Engines")
  end

  it "does not expose a non-announced speaker's profile" do
    hidden = Speaker.create!(name: "Pending Person", published: true, status: :pending)

    get speaker_path(hidden)

    expect(response).to have_http_status(:not_found)
  end
end
