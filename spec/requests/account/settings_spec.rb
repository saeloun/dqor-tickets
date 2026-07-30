require "rails_helper"

RSpec.describe "Account settings", type: :request do
  def sign_in_as(user)
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  it "requires sign-in" do
    get account_settings_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "updates name, bio and discoverability" do
    user = User.create!(email: "grace@example.com")
    sign_in_as(user)

    patch account_settings_path, params: { user: { name: "Grace Hopper", bio: "Compiler pioneer", discoverable: "1" } }

    expect(response).to redirect_to(account_settings_path)
    user.reload
    expect(user.name).to eq("Grace Hopper")
    expect(user.bio).to eq("Compiler pioneer")
    expect(user).to be_discoverable
  end

  it "sets a password when provided" do
    user = User.create!(email: "grace@example.com")
    sign_in_as(user)

    patch account_settings_path, params: { user: { password: "supersecret" } }

    expect(user.reload.authenticate("supersecret")).to be_truthy
  end

  it "keeps the existing password when the field is left blank" do
    user = User.create!(email: "grace@example.com", password: "originalpass")
    sign_in_as(user)

    patch account_settings_path, params: { user: { name: "Grace", password: "" } }

    expect(user.reload.authenticate("originalpass")).to be_truthy
  end

  it "attaches an uploaded avatar" do
    user = User.create!(email: "grace@example.com")
    sign_in_as(user)
    file = Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png")

    patch account_settings_path, params: { user: { avatar: file } }

    expect(user.reload.avatar).to be_attached
  end
end
