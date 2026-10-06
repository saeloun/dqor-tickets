module ConferenceInventory
  CAPACITY = 200
  LOCK_ID = 0x44514f52

  module_function

  def ticket_types
    TicketType.legacy.where("slug LIKE ? OR slug = ? OR (slug = ? AND hidden = ?)", "conference-pass-%", "supporter-pass", "complimentary-pass", true)
  end

  def tickets
    Ticket.legacy.where(ticket_type_id: ticket_types.select(:id))
  end

  def confirmed
    tickets.confirmed
  end

  def available_quantity(at: Time.current)
    CAPACITY - tickets.where(canceled_at: nil).joins(:order).merge(Order.legacy.reserving_inventory(at)).count
  end

  def synchronize
    Order.transaction do
      Order.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_ID})")
      yield
    end
  end
end
