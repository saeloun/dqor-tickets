require "rails_helper"

RSpec.describe "Account sessions", type: :request do
  def magic_token_for(user)
    Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
  end

  it "requires sign-in for the dashboard" do
    get account_root_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "creates an account and emails a sign-in link" do
    expect {
      post account_sign_in_path, params: { email: "New@Example.com" }
    }.to change(User, :count).by(1)

    expect(response).to redirect_to(account_sign_in_path)
    expect(User.last.email).to eq("new@example.com")
  end

  it "does not create an account for an invalid email" do
    expect {
      post account_sign_in_path, params: { email: "not-an-email" }
    }.not_to change(User, :count)
  end

  it "signs in through a valid magic link" do
    user = User.create!(email: "grace@example.com")

    get account_magic_path(token: magic_token_for(user))

    expect(response).to redirect_to(account_root_path)
    follow_redirect!
    expect(response.body).to include("grace@example.com")
  end

  it "rejects a tampered magic link" do
    get account_magic_path(token: "garbage")

    expect(response).to redirect_to(account_sign_in_path)
  end
end
