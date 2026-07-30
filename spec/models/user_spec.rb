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
