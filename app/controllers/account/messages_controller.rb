class Account::MessagesController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    @conversation = current_user.conversations.find(params[:conversation_id])
    @message = @conversation.messages.build(sender: current_user, body: message_params[:body])

    if @message.save
      @conversation.mark_read!(current_user)
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to account_conversation_path(@conversation) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "chat-composer",
            partial: "account/conversations/composer",
            locals: { conversation: @conversation, message: @message }
          ), status: :unprocessable_content
        end
        format.html { redirect_to account_conversation_path(@conversation), alert: @message.errors.full_messages.to_sentence }
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to account_conversations_path, alert: "Conversation not found."
  end

  private
    def message_params
      params.expect(message: [ :body ])
    end
end
