class Account::DashboardController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
    @tickets = current_user.tickets.includes(:ticket_type, :order).order(created_at: :desc)
    @incomplete_tickets = @tickets.select { |ticket| ticket.canceled_at.nil? && (!ticket.assigned? || ticket.details_pending?) }
    @saved_talks = current_user.bookmarked_talks.merge(Talk.published).order(Arel.sql("starts_at IS NULL"), :starts_at)
    @announcements = Announcement.published.recent.limit(3)
    @unread_announcements_count = current_user.unread_announcements_count
  end
end
