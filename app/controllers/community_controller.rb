class CommunityController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def index
    @attendees = User.where(discoverable: true)
      .where.not(id: current_user.id)
      .order(Arel.sql("lower(coalesce(name, email))"))
  end

  def show
    @attendee = User.find(params[:id])
    @connected = current_user.connected_to?(@attendee)
  end
end
