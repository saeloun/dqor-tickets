class ConnectionsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user
  before_action :require_legacy_network

  def create
    attendee = User.legacy_network.where(discoverable: true).find(params[:id])
    current_user.connections.find_or_create_by!(connected_user: attendee) unless attendee == current_user

    redirect_to attendee_path(attendee), notice: "You’re connected with #{attendee.display_name}."
  rescue ActiveRecord::RecordInvalid
    redirect_to community_path, alert: "Could not connect right now."
  end

  def destroy
    current_user.connections.where(connected_user_id: params[:id]).destroy_all

    redirect_to community_path, notice: "Connection removed."
  end
end
