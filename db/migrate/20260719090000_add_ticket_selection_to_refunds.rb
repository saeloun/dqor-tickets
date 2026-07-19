class AddTicketSelectionToRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :refunds, :ticket_ids, :json, default: [], null: false
    add_index :refunds, :razorpay_refund_id, unique: true, where: "razorpay_refund_id IS NOT NULL"
  end
end
