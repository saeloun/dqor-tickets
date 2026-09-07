class CommunityController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def index
    @query = params[:q].to_s.strip.first(80)
    attendees = User.where(discoverable: true)
      .where.not(id: current_user.id)

    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      attendees = attendees.where(
        "concat_ws(' ', name, job_title, company, conversation_starter, bio, github) ILIKE ?",
        pattern
      )
    end

    @attendees = attendees.order(Arel.sql("lower(coalesce(name, email))"))
  end

  def show
    @attendee = User.find(params[:id])
    @connected = current_user.connected_to?(@attendee)
  end
end
