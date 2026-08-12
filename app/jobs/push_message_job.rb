class PushMessageJob < ApplicationJob
  queue_as :default

  def perform(message)
    return unless WebPushNotifier.configured?

    recipient = message.conversation.other_participant(message.sender)
    return if recipient.nil?

    WebPushNotifier.deliver(
      recipient,
      title: "#{message.sender.display_name} messaged you",
      body: message.body.to_s.truncate(120),
      path: Rails.application.routes.url_helpers.account_conversation_path(message.conversation),
      tag: "conversation-#{message.conversation_id}"
    )
  end
end
