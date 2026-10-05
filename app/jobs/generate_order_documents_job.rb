class GenerateOrderDocumentsJob < ApplicationJob
  def perform(order)
    order.attach_documents!
    order.deliver_confirmation!
  rescue Invoice::DocumentPending => error
    raise unless error.cause.is_a?(InvoicePolicy::NotConfigured) && order.reload.metadata["invoice_pending_reason"] == "InvoicePolicy::NotConfigured"

    Rails.logger.warn("Invoice document requires finance review order_id=#{order.id} reason=InvoicePolicy::NotConfigured")
  end
end
