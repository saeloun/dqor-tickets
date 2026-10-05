class TicketsController < ApplicationController
  allow_unauthenticated_access

  FRIEND_COUPON = "FRIENDS".freeze

  def index
    @ticket_types = TicketType.legacy.where(hidden: false).order(:position, :id)
    @referrer = User.legacy_network.find_by(referral_code: session[:ref]) if session[:ref].present?
    @prefill_coupon = FRIEND_COUPON if @referrer
  end
end
