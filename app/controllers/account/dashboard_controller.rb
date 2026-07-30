class Account::DashboardController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
    @tickets = current_user.tickets.includes(:ticket_type, :order).order(created_at: :desc)
    @saved_talks = current_user.bookmarked_talks.merge(Talk.published).order(Arel.sql("starts_at IS NULL"), :starts_at)
    @announcements = Announcement.published.recent.limit(3)
  end
end
