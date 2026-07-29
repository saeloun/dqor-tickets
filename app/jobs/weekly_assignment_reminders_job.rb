class WeeklyAssignmentRemindersJob < ApplicationJob
  def perform
    remind_unassigned_buyers
    remind_pending_details
  end

  private
    def remind_unassigned_buyers
      order_ids = Ticket.where(assigned_at: nil, canceled_at: nil).distinct.pluck(:order_id)
      Order.paid.where(id: order_ids).find_each(&:deliver_order_link!)
    end

    def remind_pending_details
      Ticket.awaiting_details.joins(:order).merge(Order.paid).find_each do |ticket|
        ticket.request_details! if ticket.assigned?
      end
    end
end
