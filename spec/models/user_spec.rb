require "rails_helper"

RSpec.describe User, type: :model do
  it "normalizes and validates email" do
    user = build(:user, email: "  Ada@Example.COM ", name: nil)

    expect(user).not_to be_valid
    expect(user.email).to eq("ada@example.com")
    expect(user.errors).to include(:name)
  end

  it "has many identities, sessions, memberships, and registrations" do
    user = create(:user)
    identity = create(:identity, user:)
    session = create(:session, user:, admin_user: nil)
    membership = create(:membership, user:)
    registration = create(:registration, user:)

    expect(user.identities).to contain_exactly(identity)
    expect(user.sessions).to contain_exactly(session)
    expect(user.memberships).to contain_exactly(membership)
    expect(user.registrations).to contain_exactly(registration)
  end

  it "produces initials and a deterministic SVG avatar" do
    user = build(:user, name: "Ada Lovelace")

    expect(user.initials).to eq("AL")
    expect(user.initials_svg).to include("AL")
    expect(user.gravatar_url).to include(Digest::SHA256.hexdigest(user.email.downcase))
  end

  it "prefers uploaded avatar, then GitHub, then Gravatar, then initials" do
    user = create(:user, github_login: "ada")

    expect(user.avatar_image_url).to start_with("https://github.com/ada.png")

    user.github_login = nil
    expect(user.avatar_image_url).to start_with("https://www.gravatar.com/avatar/")

    user.email = nil
    expect(user.avatar_image_url).to include("<svg")
  end
end
