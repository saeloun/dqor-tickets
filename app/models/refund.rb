class Refund < ApplicationRecord
  scope :legacy, -> { joins(:order).merge(Order.legacy) }
  validate { errors.add(:order, "must belong to legacy checkout") if order&.event_id.present? }
  class AlreadyRefunded < StandardError; end
  class InvalidTransition < StandardError; end

  OPEN_STATUSES = %w[pending initiated processed].freeze

  belongs_to :order

  enum :status, { pending: "pending", initiated: "initiated", processed: "processed", failed: "failed" }, validate: true
  enum :kind, { cancellation: "cancellation", price_adjustment: "price_adjustment" }, validate: true

  validates :amount_paise, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ticket_amounts_paise_balances, on: :create

  # Refunded-so-far balance for a ticket, across every open refund of any kind
  # (cancellation or price_adjustment) — the single source of truth used to cap
  # any future refund against this ticket at its original purchase price.
  def self.refunded_paise_for(ticket)
    ticket.order.refunds.where(status: OPEN_STATUSES).sum { |refund| refund.ticket_amounts_paise.fetch(ticket.id.to_s, 0).to_i }
  end

  def process!(payment_event)
    LegacyCommerce.assert!(self)
    raise ArgumentError, "payment event belongs to another order" unless payment_event.order_id == order_id
    raise ArgumentError, "payment event amount does not match refund" unless payment_event.amount_paise == amount_paise

    # Shared order lock precedes refund/ticket locks, matching admission and
    # slot redemption and serializing retries with billing snapshot creation.
    order.with_lock do
      with_lock do
        if processed?
          return order.invoices.credit_note.find_by!(number: credit_note_number) if credit_note_number.present?
          return issue_credit_note
        end
        raise InvalidTransition, "a failed refund cannot be processed" if failed?

        invoice = order.invoices.invoice.first
        purchase_lines = invoice&.line_items || order.metadata["invoice_purchase_lines"]
        raise AlreadyRefunded, "order #{order.code} has no invoice or captured purchase lines to credit" unless purchase_lines
        owned = order.tickets.where(id: ticket_ids)
        # A price_adjustment refund never cancels its ticket, so this guard only
        # protects the cancellation path. A price_adjustment that is still
        # pending/initiated when a later cancellation refund for the same ticket
        # (already netted against it via .refunded_paise_for) processes first can
        # find its ticket already canceled — the gateway money was already sent
        # and can't be un-sent, so process! must still be allowed to finish.
        raise AlreadyRefunded, "tickets on order #{order.code} were already refunded" if cancellation? && owned.any? && owned.where(canceled_at: nil).count != owned.count

        line_items = purchase_lines.select { |line_item| ticket_ids.include?(line_item.fetch("ticket_id")) }
        raise ArgumentError, "refund has no selected tickets" if line_items.empty?

        expected_ok = if ticket_amounts_paise.present?
          ticket_amounts_paise.keys.map(&:to_i).sort == ticket_ids.sort && ticket_amounts_paise.values.sum(&:to_i) == amount_paise
        else
          line_items.sum { |line_item| line_item.fetch("total_paise") } == amount_paise
        end
        raise ArgumentError, "refund amount does not match selected tickets" unless expected_ok

        order.tickets.where(id: ticket_ids, canceled_at: nil).update_all(canceled_at: Time.current, updated_at: Time.current) if cancellation?
        update!(status: "processed")
        issue_credit_note
      end
    end
  end

  def credit_note_pending?
    processed? && credit_note_number.blank?
  end

  private
    def ticket_amounts_paise_balances
      return if ticket_amounts_paise.blank?
      errors.add(:ticket_amounts_paise, "must sum to amount_paise") unless ticket_amounts_paise.values.sum(&:to_i) == amount_paise
      errors.add(:ticket_amounts_paise, "must list exactly the refunded tickets") unless ticket_amounts_paise.keys.map(&:to_i).sort == Array(ticket_ids).sort
    end

    def issue_credit_note
      invoice = order.invoices.invoice.first
      unless invoice
        record_credit_note_pending!("InvoiceMissing")
        return
      end

      original_lines = invoice.line_items.select { |line| ticket_ids.include?(line.fetch("ticket_id")) }
      unless original_lines.size == ticket_ids.size
        record_credit_note_pending!("PurchaseLinesMismatch")
        return
      end

      synthetic = ticket_amounts_paise.present? &&
        original_lines.any? { |line| ticket_amounts_paise.fetch(line.fetch("ticket_id").to_s, 0).to_i != line.fetch("total_paise") }
      lines = synthetic ? original_lines.map { |line| Invoice.delta_line_item(line, ticket_amounts_paise.fetch(line.fetch("ticket_id").to_s).to_i) } : original_lines
      unless lines.sum { |line| line.fetch("total_paise") } == amount_paise
        record_credit_note_pending!("PurchaseLinesMismatch")
        return
      end

      begin
        credit_note = Invoice.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: lines, allow_synthetic_credit_lines: synthetic)
      rescue *Invoice::ISSUANCE_ERRORS => error
        record_credit_note_pending!(error.class.name)
        return
      end
      update!(credit_note_number: credit_note.number)
      order.with_lock do
        pending = order.metadata.fetch("credit_notes_pending", {}).except(id.to_s)
        order.update!(metadata: order.metadata.merge("credit_notes_pending" => pending))
      end
      credit_note
    end

    def record_credit_note_pending!(reason)
      order.with_lock do
        pending = order.metadata.fetch("credit_notes_pending", {}).merge(id.to_s => reason)
        order.update!(metadata: order.metadata.merge("credit_notes_pending" => pending))
      end
    end
end
