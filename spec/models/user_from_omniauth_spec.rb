require "rails_helper"

RSpec.describe UserFromOmniauth do
  def auth_payload(email: "ada@example.com", verified: true, nickname: "ada", name: "Ada Lovelace")
    OmniAuth::AuthHash.new(
      provider: "github",
      uid: "12345",
      info: {
        email: email,
        nickname: nickname,
        name: name
      },
      extra: {
        raw_info: {
          email_verified: verified
        }
      }
    )
  end

  it "creates a new user and identity for a fresh GitHub login" do
    user = described_class.find_or_create!(auth_payload)

    expect(user).to be_persisted
    expect(user.email).to eq("ada@example.com")
    expect(user.github_login).to eq("ada")
    expect(user.identities.github.find_by(uid: "12345")).to be_present
  end

  it "links an existing user by verified email" do
    existing = create(:user, email: "ada@example.com")

    user = described_class.find_or_create!(auth_payload)

    expect(user).to eq(existing)
    expect(existing.identities.github.find_by(uid: "12345")).to be_present
  end

  it "does not link by unverified email" do
    create(:user, email: "ada@example.com")

    expect {
      described_class.find_or_create!(auth_payload(verified: false))
    }.to raise_error(described_class::UnverifiedEmail)
  end

  it "returns the same user when the identity already exists" do
    existing = create(:user, email: "ada@example.com")
    create(:identity, user: existing, provider: "github", uid: "12345")

    user = described_class.find_or_create!(auth_payload)

    expect(user).to eq(existing)
  end
end
