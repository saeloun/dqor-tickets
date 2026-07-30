require "rails_helper"

RSpec.describe WebPushNotifier do
  let!(:subscription) do
    PushSubscription.create!(endpoint: "https://push.example/x", p256dh_key: "p", auth_key: "a")
  end

  it "sends an encrypted payload signed with the VAPID keys" do
    expect(WebPush).to receive(:payload_send).with(
      hash_including(
        endpoint: "https://push.example/x",
        p256dh: "p",
        auth: "a",
        vapid: hash_including(public_key: Vapid.public_key, private_key: Vapid.private_key, subject: Vapid::SUBJECT)
      )
    )

    WebPushNotifier.deliver(title: "Doors open", body: "Registration is open", path: "/")
  end

  it "prunes subscriptions the push service has expired" do
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription.allocate)

    expect {
      WebPushNotifier.deliver(title: "x", body: "y")
    }.to change(PushSubscription, :count).by(-1)
  end
end
