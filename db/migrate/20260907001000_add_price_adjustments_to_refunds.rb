class AddPriceAdjustmentsToRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :refunds, :reason, :string, null: false, default: "ticket_cancellation"
    add_column :refunds, :line_items, :json, null: false, default: []
    add_column :refunds, :reference, :string
    add_index :refunds, :reference, unique: true, where: "reference IS NOT NULL"
  end
end
