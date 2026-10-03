class Account::RedemptionsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_user
  before_action :require_verified_email

  def index
    response.headers["Cache-Control"] = "no-store"
    @checked_at = Time.current
    @tickets = Ticket.legacy.where("lower(attendee_email) = ?", current_user.email).includes(:ticket_type, :order)
    @slots = EventSlot.where(active: true).order(:starts_at)
    @redemptions = EventSlotRedemption.where(ticket_id: @tickets.select(:id)).includes(:event_slot).group_by(&:ticket_id)
  end
  private
    def require_verified_email
      return if current_user && session[:verified_attendee_email] == current_user.email

      redirect_to account_sign_in_path, alert: "Use the email sign-in link to verify your ticket email before viewing scan status."
    end
end
