require "rails_helper"

RSpec.describe "Community", type: :request do
  def sign_in_as(user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  it "requires sign-in" do
    get community_path

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "lists discoverable attendees except yourself" do
    me = User.create!(email: "me@example.com", name: "Zephyr Selftest", discoverable: true)
    User.create!(email: "ada@example.com", name: "Ada Discoverable", discoverable: true)
    User.create!(email: "hidden@example.com", name: "Hidden Person", discoverable: false)
    sign_in_as(me)

    get community_path

    expect(response.body).to include("Ada Discoverable")
    expect(response.body).not_to include("Hidden Person")
    expect(response.body).not_to include("Zephyr Selftest")
  end

  it "shows a discoverable attendee profile with a connect action" do
    me = User.create!(email: "me@example.com")
    ada = User.create!(email: "ada@example.com", name: "Ada", discoverable: true)
    sign_in_as(me)

    get attendee_path(ada)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ada")
    expect(response.body).to include("Connect")
  end
end
