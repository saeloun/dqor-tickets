class ConnectionsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    attendee = User.where.not(id: current_user.id).find(params[:id])
    current_user.connections.find_or_create_by!(connected_user: attendee)
    conversation = Conversation.between(current_user, attendee)

    redirect_to account_conversation_path(conversation)
  rescue ActiveRecord::RecordInvalid
    redirect_to community_path, alert: "Could not connect right now."
  end

  def destroy
    attendee = User.find(params[:id])
    current_user.connections.where(connected_user: attendee).destroy_all

    redirect_to community_path, notice: "Connection removed."
  end
end
