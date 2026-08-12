class Message < ApplicationRecord
  belongs_to :conversation, touch: true
  belongs_to :sender, class_name: "User"

  validates :body, presence: true, length: { maximum: 2000 }

  after_create_commit :broadcast_to_conversation
  after_create_commit :push_to_recipient

  private
    def broadcast_to_conversation
      broadcast_append_to(
        conversation,
        target: "chat-messages",
        partial: "account/messages/message",
        locals: { message: self }
      )
    end

    def push_to_recipient
      PushMessageJob.perform_later(self)
    end
end
