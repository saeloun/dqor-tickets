class Message < ApplicationRecord
  belongs_to :conversation, touch: true
  belongs_to :sender, class_name: "User"

  validates :body, presence: true, length: { maximum: 2000 }

  validate do
    unless sender && conversation&.has_participant?(sender) && conversation.participants.all?(&:legacy_network_eligible?)
      errors.add(:base, "Networking unavailable")
    end
  end

  after_create_commit :broadcast_to_conversation
  after_create_commit :push_to_recipient

  private
    def broadcast_to_conversation
      return unless conversation.participants.all?(&:legacy_network_eligible?)
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
