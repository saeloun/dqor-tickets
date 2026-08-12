class Account::ConversationsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def index
    @conversations = current_user.conversations
      .includes(:participant_one, :participant_two, :messages)
      .order(updated_at: :desc)
  end

  def show
    @conversation = current_user.conversations.find(params[:id])
    @other = @conversation.other_participant(current_user)
    @messages = @conversation.messages.includes(:sender)
    @message = Message.new
    @conversation.mark_read!(current_user)
  rescue ActiveRecord::RecordNotFound
    redirect_to account_conversations_path, alert: "Conversation not found."
  end

  def create
    other = User.find(params.require(:attendee_id))

    unless current_user.can_message?(other)
      redirect_to community_path, alert: "You can only message attendees you’ve connected with."
      return
    end

    conversation = Conversation.between(current_user, other)
    redirect_to account_conversation_path(conversation)
  rescue ActiveRecord::RecordNotFound
    redirect_to community_path, alert: "Attendee not found."
  end
end
