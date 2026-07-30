class ScheduleController < ApplicationController
  allow_unauthenticated_access

  def show
    @talks_by_day = Talk.published.scheduled.group_by(&:day)
  end
end
