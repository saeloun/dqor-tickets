require "rails_helper"

RSpec.describe "GitHub sign-in", type: :request do
  before { OmniAuth.config.test_mode = true }

  after do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  def mock_github(email:, name: "Ruby Fan", nickname: "rubyfan")
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "gh-123", info: { email: email, name: name, nickname: nickname }
    )
  end

  it "creates and signs in a user with their shared RubyEvents identity" do
    mock_github(email: "new@example.com", name: "New Person", nickname: "newperson")

    expect { get "/auth/github/callback" }.to change { User.count }.by(1)

    user = User.find_by!(email: "new@example.com")
    expect(response).to redirect_to(account_root_path)
    expect(user).to have_attributes(name: "New Person", github: "newperson")
  end

  it "links an existing email without duplicating the user" do
    user = User.create!(email: "existing@example.com")
    mock_github(email: user.email, nickname: "existing")

    expect { get "/auth/github/callback" }.not_to change { User.count }

    expect(response).to redirect_to(account_root_path)
    expect(user.reload.github).to eq("existing")
  end

  it "falls back to the email link when GitHub returns no email" do
    mock_github(email: "")

    get "/auth/github/callback"

    expect(response).to redirect_to(account_sign_in_path)
  end
end
