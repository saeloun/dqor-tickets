class WeeklyAssignmentRemindersJob < ApplicationJob
  def perform
    return if Conference.status == :after

    remind_unassigned_buyers
    remind_pending_details
  end

  private
    def remind_unassigned_buyers
      order_ids = Ticket.legacy.where(assigned_at: nil, canceled_at: nil).distinct.pluck(:order_id)
      Order.legacy.paid.where(id: order_ids).find_each do |order|
        OrderMailer.with(weekly_assignment_reminder: true).order_link(order).deliver_later
      end
    end

    def remind_pending_details
      Ticket.awaiting_details.joins(:order).merge(Order.legacy.paid).find_each do |ticket|
        OrderMailer.with(weekly_assignment_reminder: true).complete_details(ticket).deliver_later if ticket.assigned?
      end
    end
end
