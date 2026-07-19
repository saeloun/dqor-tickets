class ReconcilePaymentsJob < ApplicationJob
  def perform
    Order.reconcile_pending_payments!
  end
end
