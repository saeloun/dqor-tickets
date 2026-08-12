require "rails_helper"

RSpec.describe PushMessageJob, type: :job do
  let(:ana) { User.create!(email: "ana@example.com", name: "Ana") }
  let(:bo) { User.create!(email: "bo@example.com", name: "Bo") }

  it "pushes to the other participant" do
    conversation = Conversation.between(ana, bo)
    message = conversation.messages.create!(sender: ana, body: "hi Bo")

    allow(WebPushNotifier).to receive(:configured?).and_return(true)
    allow(WebPushNotifier).to receive(:deliver)

    described_class.perform_now(message)

    expect(WebPushNotifier).to have_received(:deliver)
      .with(bo, hash_including(title: "Ana messaged you", tag: "conversation-#{conversation.id}"))
  end

  it "does nothing when web push is unconfigured" do
    conversation = Conversation.between(ana, bo)
    message = conversation.messages.create!(sender: ana, body: "hi")
    allow(WebPushNotifier).to receive(:configured?).and_return(false)

    expect(WebPushNotifier).not_to receive(:deliver)
    described_class.perform_now(message)
  end
end
