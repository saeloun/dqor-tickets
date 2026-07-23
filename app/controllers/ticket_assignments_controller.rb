class TicketAssignmentsController < ApplicationController
  allow_unauthenticated_access

  before_action :set_ticket

  def show
  end

  def update
    @ticket.assign!(**assignment_params)
    redirect_to assignment_return_path, notice: "Ticket assigned to #{@ticket.attendee_name}."
  rescue Ticket::Canceled, ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error_message(error)
    render assignment_template, status: :unprocessable_content
  end

  private
    def set_ticket
      if claim_request?
        @ticket = Ticket.joins(:order).merge(Order.paid).find_by!(claim_token: params.expect(:claim_token))
      else
        @order = Order.paid.find_by!(code: params.expect(:code))
        @ticket = @order.tickets.find(params.expect(:id))
      end
    end

    def assignment_params
      params.expect(ticket: [ :attendee_name, :attendee_email, :dietary_preference, :childcare_needed, :tshirt_size ]).to_h.symbolize_keys
    end

    def claim_request?
      params[:claim_token].present?
    end

    def assignment_return_path
      claim_request? ? ticket_claim_path(@ticket.claim_token) : order_path(@order.code)
    end

    def assignment_template
      claim_request? ? :show : "orders/show"
    end

    def error_message(error)
      error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
    end
end
