class ProcessRefundJob < ApplicationJob
  def perform(refund_id, payment_event_id)
    refund = Refund.legacy.find(refund_id)
    credit_note = refund.process!(refund.order.payment_events.find(payment_event_id))
    raise Invoice::DocumentPending, "processed refund awaits its accounting document" if refund.credit_note_pending?
    return unless credit_note

    credit_note.attach_pdf!
    if refund.price_adjustment?
      OrderMailer.price_adjustment_refund_note(refund).deliver_later
    else
      OrderMailer.refund_note(refund).deliver_later
    end
  end
end
