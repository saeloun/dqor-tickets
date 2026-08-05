class Avo::ToolsController < Avo::ApplicationController
  def dashboard
    @page_title = "Sales dashboard"
    @gross_revenue = Order.paid.sum(:total_paise)
    @net_revenue = @gross_revenue - Refund.where(status: "processed").sum(:amount_paise)
    paid_tickets = Ticket.where(canceled_at: nil).joins(:order).merge(Order.paid)
    @total_sold = paid_tickets.count
    @assigned = paid_tickets.where.not(attendee_email: [ nil, "" ]).count
    @checked_in = paid_tickets.where("tickets.checked_in_at::text <> '{}'").count
    sold = paid_tickets.group(:ticket_type_id).count
    @sold_by_type = TicketType.order(:position, :id).map { |ticket_type| [ ticket_type, sold.fetch(ticket_type.id, 0) ] }
    @orders_last_seven_days = Order.where(created_at: 7.days.ago..).group("date(created_at)").count
    add_breadcrumb title: "Sales dashboard"
  end
end
