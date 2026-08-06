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

    assigned = paid_tickets.where.not(attendee_email: [ nil, "" ])
    tshirt = assigned.where.not(tshirt_size: [ nil, "" ]).group(:tshirt_size).count
    @tshirt_counts = Ticket::TSHIRT_SIZES.index_with { |size| tshirt.fetch(size, 0) }
    @tshirt_unspecified = assigned.where("tshirt_size IS NULL OR tshirt_size = ''").count
    @dietary_counts = assigned.where.not(dietary_preference: [ nil, "" ])
      .group(:dietary_preference).order(Arel.sql("count(*) DESC")).count
    @childcare_needed = assigned.where(childcare_needed: true).count

    add_breadcrumb title: "Sales dashboard"
  end
end
