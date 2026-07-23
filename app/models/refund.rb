class Refund < ApplicationRecord
  class AlreadyRefunded < StandardError; end

  OPEN_STATUSES = %w[pending initiated processed].freeze

  belongs_to :order

  validates :status, presence: true
  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def process!(payment_event)
    raise ArgumentError, "payment event belongs to another order" unless payment_event.order_id == order_id
    raise ArgumentError, "payment event amount does not match refund" unless payment_event.amount_paise == amount_paise

    with_lock do
      return order.invoices.credit_note.find_by!(number: credit_note_number) if status == "processed"

      invoice = order.invoices.invoice.first or raise AlreadyRefunded, "order #{order.code} has no invoice to credit"
      owned = order.tickets.where(id: ticket_ids)
      raise AlreadyRefunded, "tickets on order #{order.code} were already refunded" if owned.any? && owned.where(canceled_at: nil).count != owned.count

      line_items = invoice.line_items.select { |line_item| ticket_ids.include?(line_item.fetch("ticket_id")) }
      raise ArgumentError, "refund has no selected tickets" if line_items.empty?
      raise ArgumentError, "refund amount does not match selected tickets" unless line_items.sum { |line_item| line_item.fetch("total_paise") } == amount_paise

      order.tickets.where(id: ticket_ids, canceled_at: nil).update_all(canceled_at: Time.current, updated_at: Time.current)
      credit_note = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items:)
      update!(status: "processed", credit_note_number: credit_note.number)
      credit_note
    end
  end
end
