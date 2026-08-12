require "rails_helper"

RSpec.describe "Google sign-in", type: :request do
  before { OmniAuth.config.test_mode = true }

  after do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_google(email:, name: "Ruby Fan")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-123", info: { email: email, name: name }
    )
  end

  it "creates and signs in a new user from Google" do
    mock_google(email: "new@example.com", name: "New Person")

    expect { get "/auth/google_oauth2/callback" }.to change { User.count }.by(1)
    expect(response).to redirect_to(account_root_path)
    expect(User.find_by(email: "new@example.com").name).to eq("New Person")
  end

  it "signs in an existing user without duplicating, and the session sticks" do
    User.create!(email: "existing@example.com", name: "Existing")
    mock_google(email: "existing@example.com")

    expect { get "/auth/google_oauth2/callback" }.not_to change { User.count }
    expect(response).to redirect_to(account_root_path)

    get account_root_path
    expect(response).to have_http_status(:ok)
  end

  it "falls back to the email link when Google returns no email" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", info: { email: "" })

    get "/auth/google_oauth2/callback"

    expect(response).to redirect_to(account_sign_in_path)
  end
end
