class DeliverOrderConfirmationJob < ApplicationJob
  def perform(order)
    order.deliver_confirmation!
  end
end
