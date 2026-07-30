class ScheduleController < ApplicationController
  allow_unauthenticated_access

  def show
    @talks_by_day = Talk.published.scheduled.group_by(&:day)
    @bookmarked_ids = current_user ? current_user.talk_bookmarks.pluck(:talk_id).to_set : Set.new
  end
end
