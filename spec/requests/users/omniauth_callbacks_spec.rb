require "rails_helper"

RSpec.describe "GitHub OAuth callback", type: :request do
  def github_auth_hash(email: "ada@example.com", verified: true, nickname: "ada", name: "Ada Lovelace")
    OmniAuth::AuthHash.new(
      provider: "github",
      uid: "12345",
      info: { email: email, nickname: nickname, name: name },
      extra: { raw_info: { email_verified: verified } }
    )
  end

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = github_auth_hash
  end

  after do
    OmniAuth.config.mock_auth[:github] = nil
  end

  it "signs in a new user and redirects" do
    expect { get github_callback_path }.to change(User, :count).by(1).and change(Session, :count).by(1)

    expect(response).to redirect_to(rails_health_check_url)
  end

  it "links an existing user by verified email" do
    user = create(:user, email: "ada@example.com")

    expect { get github_callback_path }.not_to change(User, :count)
    expect(user.identities.github.find_by(uid: "12345")).to be_present
    expect(response).to redirect_to(rails_health_check_url)
  end

  it "rejects an unverified email without linking" do
    create(:user, email: "ada@example.com")
    OmniAuth.config.mock_auth[:github] = github_auth_hash(verified: false)

    expect { get github_callback_path }.not_to change(User, :count)
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to include("verify")
  end

  it "shows a failure message on auth failure" do
    get auth_failure_path

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to include("failed")
  end
end
