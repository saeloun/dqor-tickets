class ScheduleController < ApplicationController
  allow_unauthenticated_access

  def show
    @talks_by_day = Talk.published.scheduled.group_by(&:day)
    @bookmarked_ids = current_user ? current_user.talk_bookmarks.pluck(:talk_id).to_set : Set.new

    now = Time.current
    timed = Talk.published.where.not(starts_at: nil)
    @now_talk = timed.where("starts_at <= ? AND (ends_at IS NULL OR ends_at >= ?)", now, now).order(:starts_at).first
    @next_talk = timed.where("starts_at > ?", now).order(:starts_at).first
  end
end
