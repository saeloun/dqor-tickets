class GenerateOrderDocumentsJob < ApplicationJob
  def perform(order)
    order.attach_documents!
    order.deliver_confirmation!
  end
end
