class Refund < ApplicationRecord
  class AlreadyRefunded < StandardError; end
  class InvalidTransition < StandardError; end

  OPEN_STATUSES = %w[pending initiated processed].freeze

  belongs_to :order

  enum :status, { pending: "pending", initiated: "initiated", processed: "processed", failed: "failed" }, validate: true
  enum :reason, { ticket_cancellation: "ticket_cancellation", price_adjustment: "price_adjustment" }, validate: true

  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reference, uniqueness: true, allow_nil: true

  def process!(payment_event)
    raise ArgumentError, "payment event belongs to another order" unless payment_event.order_id == order_id
    raise ArgumentError, "payment event amount does not match refund" unless payment_event.amount_paise == amount_paise

    with_lock do
      return order.invoices.credit_note.find_by!(number: credit_note_number) if processed?
      raise InvalidTransition, "a failed refund cannot be processed" if failed?

      invoice = order.invoices.invoice.first or raise AlreadyRefunded, "order #{order.code} has no invoice to credit"
      owned = order.tickets.where(id: ticket_ids)
      raise ArgumentError, "refund has no selected tickets" if owned.empty?
      raise ArgumentError, "refund contains tickets from another order" unless owned.count == ticket_ids.size
      if ticket_cancellation? && owned.where(canceled_at: nil).count != owned.count
        raise AlreadyRefunded, "tickets on order #{order.code} were already refunded"
      end

      refund_lines = line_items.presence || invoice.line_items.select { |line_item| ticket_ids.include?(line_item.fetch("ticket_id")) }
      raise ArgumentError, "refund has no selected tickets" if refund_lines.empty?
      raise ArgumentError, "refund lines do not match selected tickets" unless refund_lines.pluck("ticket_id").sort == ticket_ids.sort
      raise ArgumentError, "refund amount does not match selected tickets" unless refund_lines.sum { |line_item| line_item.fetch("total_paise") } == amount_paise

      order.tickets.where(id: ticket_ids, canceled_at: nil).update_all(canceled_at: Time.current, updated_at: Time.current) if ticket_cancellation?
      credit_note = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: refund_lines)
      update!(status: "processed", credit_note_number: credit_note.number)
      credit_note
    end
  end
end
