class BackfillMultiGateway < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      UPDATE orders SET gateway_reference = razorpay_order_id
      WHERE gateway_reference IS NULL AND razorpay_order_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE payment_events SET gateway_event_id = razorpay_event_id
      WHERE gateway_event_id IS NULL AND razorpay_event_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE payment_events SET gateway_payment_id = razorpay_payment_id
      WHERE gateway_payment_id IS NULL AND razorpay_payment_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE refunds SET gateway_refund_id = razorpay_refund_id
      WHERE gateway_refund_id IS NULL AND razorpay_refund_id IS NOT NULL
    SQL
  end

  def down
    execute "UPDATE orders SET gateway_reference = NULL"
    execute "UPDATE payment_events SET gateway_event_id = NULL, gateway_payment_id = NULL"
    execute "UPDATE refunds SET gateway_refund_id = NULL"
  end
end
