require "rails_helper"

RSpec.describe "Push subscriptions", type: :request do
  let(:payload) do
    { subscription: { endpoint: "https://push.example/abc", keys: { p256dh: "PKEY", auth: "AKEY" } } }
  end

  it "stores a push subscription" do
    expect {
      post push_subscriptions_path, params: payload, as: :json
    }.to change(PushSubscription, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(PushSubscription.last).to have_attributes(endpoint: "https://push.example/abc", p256dh_key: "PKEY", auth_key: "AKEY")
  end

  it "is idempotent on the same endpoint" do
    post push_subscriptions_path, params: payload, as: :json

    expect {
      post push_subscriptions_path, params: payload, as: :json
    }.not_to change(PushSubscription, :count)
  end
end
