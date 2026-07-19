class GenerateOrderDocumentsJob < ApplicationJob
  def perform(order)
    order.attach_documents!
  end
end
