class AddLevelAndModeToPaymentEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_events, :level, :string, default: "info", null: false
    add_column :payment_events, :mode, :string
  end
end
