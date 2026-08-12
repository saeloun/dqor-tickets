require "rails_helper"

RSpec.describe "Account push subscriptions", type: :request do
  def sign_in_as(user)
    get account_magic_path(
      token: Rails.application.message_verifier(:account_magic_link)
        .generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    )
  end

  let(:params) do
    { subscription: { endpoint: "https://push.example.com/abc", keys: { p256dh: "p256key", auth: "authkey" } } }
  end

  it "requires sign-in" do
    post account_push_subscriptions_path, params: params, as: :json

    expect(response).to redirect_to(account_sign_in_path)
  end

  it "stores a subscription for the signed-in user" do
    user = User.create!(email: "push@example.com")
    sign_in_as(user)

    expect { post account_push_subscriptions_path, params: params, as: :json }
      .to change { user.push_subscriptions.count }.by(1)

    expect(response).to have_http_status(:created)
    subscription = user.push_subscriptions.last
    expect(subscription.endpoint).to eq("https://push.example.com/abc")
    expect(subscription.p256dh).to eq("p256key")
    expect(subscription.auth).to eq("authkey")
  end

  it "upserts by endpoint instead of duplicating" do
    user = User.create!(email: "push2@example.com")
    sign_in_as(user)
    post account_push_subscriptions_path, params: params, as: :json

    expect { post account_push_subscriptions_path, params: params, as: :json }
      .not_to change { user.push_subscriptions.count }
  end

  it "removes a subscription by endpoint" do
    user = User.create!(email: "push3@example.com")
    user.push_subscriptions.create!(endpoint: "https://push.example.com/x", p256dh: "p", auth: "a")
    sign_in_as(user)

    expect { delete account_push_subscriptions_path, params: { endpoint: "https://push.example.com/x" }, as: :json }
      .to change { user.push_subscriptions.count }.by(-1)
  end
end
