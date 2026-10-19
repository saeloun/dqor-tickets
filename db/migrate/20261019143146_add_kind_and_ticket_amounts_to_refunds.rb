class AddKindAndTicketAmountsToRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :refunds, :kind, :string, null: false, default: "cancellation"
    add_column :refunds, :ticket_amounts_paise, :json, null: false, default: {}
    add_index :refunds, :kind
  end
end
