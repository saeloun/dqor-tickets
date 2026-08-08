require "rails_helper"

RSpec.describe User do
  it "normalizes and requires a unique email" do
    User.create!(email: "  Grace@Example.COM ")

    expect(User.last.email).to eq("grace@example.com")
    expect(User.new(email: "grace@example.com")).not_to be_valid
  end

  it "allows no password but enforces length once one is set" do
    user = User.new(email: "a@b.com")
    expect(user).to be_valid

    user.password = "short"
    expect(user).not_to be_valid

    user.password = "longenough"
    expect(user).to be_valid
  end

  it "normalizes social profile fields" do
    user = User.create!(
      email: "social@example.com",
      website: " example.com/about ",
      x_username: " @grace ",
      bluesky: "@grace.bsky.social",
      github: "@ghopper",
      mastodon: "@grace@ruby.social",
      linkedin: "@grace-hopper"
    )

    expect(user).to have_attributes(
      website: "https://example.com/about",
      x_username: "grace",
      bluesky: "grace.bsky.social",
      github: "ghopper",
      mastodon: "grace@ruby.social",
      linkedin: "grace-hopper"
    )
  end

  it "validates social profile lengths and requires an http website URL" do
    user = User.new(email: "social@example.com", website: "ftp://example.com", github: "g" * 256)

    expect(user).not_to be_valid
    expect(user.errors[:website]).to include("must be a valid http(s) URL")
    expect(user.errors[:github]).to include("is too long (maximum is 255 characters)")
  end

  it "builds a Gravatar URL from the email hash" do
    user = User.new(email: "grace@example.com")

    expect(user.gravatar_url).to include(Digest::MD5.hexdigest("grace@example.com"))
    expect(user.gravatar_url).to include("gravatar.com")
  end

  it "finds paid tickets by matching email, case-insensitively" do
    order = create(:order, :paid, email: "grace@example.com")
    ticket = create(:ticket, order:)
    user = User.create!(email: "GRACE@example.com")

    expect(user.tickets).to include(ticket)
  end
end
