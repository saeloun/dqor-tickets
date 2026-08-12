require "rails_helper"

RSpec.describe PushAnnouncementJob, type: :job do
  let(:announcement) { Announcement.create!(title: "Schedule is live", body: "Come see the talks", published: true, published_at: Time.current) }

  it "pushes to users who have a subscription" do
    subscribed = User.create!(email: "sub@example.com")
    subscribed.push_subscriptions.create!(endpoint: "e", p256dh: "p", auth: "a")
    User.create!(email: "nosub@example.com")

    allow(WebPushNotifier).to receive(:configured?).and_return(true)
    allow(WebPushNotifier).to receive(:deliver)

    described_class.perform_now(announcement)

    expect(WebPushNotifier).to have_received(:deliver)
      .with(subscribed, hash_including(title: "Schedule is live", path: "/updates")).once
  end

  it "does nothing when web push is not configured" do
    user = User.create!(email: "sub2@example.com")
    user.push_subscriptions.create!(endpoint: "e2", p256dh: "p", auth: "a")
    allow(WebPushNotifier).to receive(:configured?).and_return(false)

    expect(WebPushNotifier).not_to receive(:deliver)
    described_class.perform_now(announcement)
  end
end
