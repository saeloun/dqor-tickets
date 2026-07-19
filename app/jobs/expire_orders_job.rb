class ExpireOrdersJob < ApplicationJob
  def perform
    Order.expire_overdue!
  end
end
