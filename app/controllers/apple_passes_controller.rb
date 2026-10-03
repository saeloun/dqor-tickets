class ApplePassesController < ApplicationController
  allow_unauthenticated_access

  def show
    return head :not_found unless PkpassGenerator.configured?

    ticket = Ticket.confirmed.find_by!(secret: params[:secret])

    send_data PkpassGenerator.new(ticket).generate,
      filename: "deccan-queen-on-rails.pkpass",
      type: "application/vnd.apple.pkpass",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
