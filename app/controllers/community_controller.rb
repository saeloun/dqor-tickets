class CommunityController < ApplicationController
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
  allow_unauthenticated_access
  before_action :require_user
  before_action :require_legacy_network

  def index
    @attendees = User.legacy_network.where(discoverable: true)
      .where.not(id: current_user.id)
      .order(Arel.sql("lower(coalesce(name, email))"))
  end

  def show
    @attendee = User.legacy_network.where(discoverable: true).find(params[:id])
    @connected = current_user.connected_to?(@attendee)
  end
end
