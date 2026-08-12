class Account::CalendarsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
    talks = current_user.bookmarked_talks.merge(Talk.published)
      .where.not(starts_at: nil).order(:starts_at)

    send_data ScheduleIcs.new(talks).to_ics.gsub("\n", "\r\n"),
      filename: "my-dqor-schedule.ics",
      type: "text/calendar",
      disposition: "attachment"
  end
end
