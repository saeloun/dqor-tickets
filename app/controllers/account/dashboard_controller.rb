class Account::DashboardController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user

  def show
    @tickets = current_user.tickets.includes(:ticket_type, :order).order(created_at: :desc)
  end
end
