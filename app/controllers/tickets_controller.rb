class TicketsController < ApplicationController
  allow_unauthenticated_access

  def index
    @ticket_types = TicketType.where(hidden: false).order(:position, :id)
  end
end
