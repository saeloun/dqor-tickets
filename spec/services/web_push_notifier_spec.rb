require "rails_helper"

RSpec.describe WebPushNotifier do
  let(:user) { User.create!(email: "notify@example.com") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VAPID_PUBLIC_KEY").and_return("pub")
    allow(ENV).to receive(:[]).with("VAPID_PRIVATE_KEY").and_return("priv")
    allow(ENV).to receive(:[]).with("VAPID_SUBJECT").and_return("mailto:test@example.com")
  end

  it "reports configured when both keys are present" do
    expect(described_class).to be_configured
  end

  it "sends nothing and returns 0 when unconfigured" do
    allow(ENV).to receive(:[]).with("VAPID_PUBLIC_KEY").and_return(nil)
    user.push_subscriptions.create!(endpoint: "e", p256dh: "p", auth: "a")

    expect(WebPush).not_to receive(:payload_send)
    expect(described_class.deliver(user, title: "t", body: "b")).to eq(0)
  end

  it "delivers to every subscription and counts successes" do
    user.push_subscriptions.create!(endpoint: "e1", p256dh: "p", auth: "a")
    user.push_subscriptions.create!(endpoint: "e2", p256dh: "p", auth: "a")
    allow(WebPush).to receive(:payload_send)

    expect(described_class.deliver(user, title: "Hi", body: "There", path: "/updates")).to eq(2)
    expect(WebPush).to have_received(:payload_send).twice
  end

  it "drops a subscription the push service reports as gone" do
    user.push_subscriptions.create!(endpoint: "dead", p256dh: "p", auth: "a")
    response = instance_double(Net::HTTPResponse, body: "gone")
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription.new(response, "push.example.com"))

    expect { described_class.deliver(user, title: "t", body: "b") }
      .to change { user.push_subscriptions.count }.by(-1)
  end

  it "keeps the subscription and swallows a transient error" do
    user.push_subscriptions.create!(endpoint: "flaky", p256dh: "p", auth: "a")
    allow(WebPush).to receive(:payload_send).and_raise(StandardError, "boom")

    expect { expect(described_class.deliver(user, title: "t", body: "b")).to eq(0) }
      .not_to change { user.push_subscriptions.count }
  end
end
