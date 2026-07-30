class TalkBookmarksController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def create
    talk = Talk.published.find(params[:talk_id])
    current_user.talk_bookmarks.find_or_create_by!(talk: talk)

    redirect_back fallback_location: schedule_path
  end

  def destroy
    current_user.talk_bookmarks.where(talk_id: params[:talk_id]).destroy_all

    redirect_back fallback_location: schedule_path
  end
end
