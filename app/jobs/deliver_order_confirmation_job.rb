class DeliverOrderConfirmationJob < ApplicationJob
  def perform(order)
    order.deliver_confirmation!
  rescue *DOCUMENT_ERRORS
    order.deliver_confirmation!(documents_pending: true)
    GenerateOrderDocumentsJob.perform_later(order)
  end
end
