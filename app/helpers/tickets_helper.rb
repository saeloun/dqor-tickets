module TicketsHelper
  def ticket_sale_state(ticket_type, available:, at: Time.current)
    return "coming soon" if ticket_type.sales_start_at && ticket_type.sales_start_at > at
    return "sales closed" if ticket_type.sales_end_at && ticket_type.sales_end_at < at
    return "sales closed" if !ticket_type.active? && %w[conference-pass-early-bird conference-pass-regular].include?(ticket_type.slug)
    return "coming soon" unless ticket_type.purchasable?(at: at)

    available.positive? ? "on sale" : "sold out"
  end
end
