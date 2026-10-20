require "rails_helper"

RSpec.describe "Avo speaker talks", type: :request do
  let!(:speaker) { Speaker.create!(name: "Synthetic speaker") }
  let!(:talk) { Talk.create!(title: "Synthetic associated talk", speaker: speaker) }

  it "loads the speaker's talks association" do
    sign_in_admin
    get "/avo/resources/speakers/#{speaker.id}/talks"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.text).to include(talk.title)
  end

  it "returns not found for an unknown association" do
    sign_in_admin
    get "/avo/resources/speakers/#{speaker.id}/talk"

    expect(response).to have_http_status(:not_found)
  end

  it "preserves the declared belongs-to link on a talk" do
    sign_in_admin
    get "/avo/resources/talks/#{talk.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.text).to include(speaker.name)
  end

  it "returns not found for a field unsupported by the collection route" do
    sign_in_admin
    get "/avo/resources/talks/#{talk.id}/speaker"

    expect(response).to have_http_status(:not_found)
  end

  it "keeps anonymous visitors out of the association" do
    get "/avo/resources/speakers/#{speaker.id}/talks"

    expect(response).to redirect_to("/session/new")
  end

  it "keeps desk staff on the scanner" do
    sign_in_admin(create(:admin_user, role: :desk))
    get "/avo/resources/speakers/#{speaker.id}/talks"

    expect(response).to redirect_to("/checkin")
  end
end
