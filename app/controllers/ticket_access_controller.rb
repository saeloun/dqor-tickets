class TicketAccessController < ApplicationController
  allow_unauthenticated_access

  TOKEN_PURPOSE = :ticket_access
  TOKEN_EXPIRY = 24.hours
  SENT_NOTICE = "If we have tickets for that address, we have sent a link. Check your inbox."

  rate_limit to: 5, within: 5.minutes, only: :create, with: -> { redirect_to find_tickets_path, alert: "Please wait before requesting another link." }

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase

    if orders_for(email).exists?
      TicketAccessMailer.link(email, generate_token(email)).deliver_later
    end

    redirect_to find_tickets_path, notice: SENT_NOTICE
  end

  def show
    @email = verifier.verified(params.expect(:token), purpose: TOKEN_PURPOSE)

    if @email.blank?
      return redirect_to find_tickets_path, alert: "That link is invalid or has expired. Request a new one."
    end

    @orders = orders_for(@email).order(created_at: :desc).includes(tickets: :ticket_type)
  end

  private
    def orders_for(email)
      Order.paid.where("lower(orders.email) = ?", email)
    end

    def generate_token(email)
      verifier.generate(email, purpose: TOKEN_PURPOSE, expires_in: TOKEN_EXPIRY)
    end

    def verifier
      Rails.application.message_verifier(:ticket_access)
    end
end
