class GoogleWalletPassesController < ApplicationController
  allow_unauthenticated_access

  def show
    return head :not_found unless GoogleWalletGenerator.configured?

    ticket = Ticket.confirmed.find_by!(secret: params[:secret])

    redirect_to GoogleWalletGenerator.new(ticket).save_url, allow_other_host: true
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
