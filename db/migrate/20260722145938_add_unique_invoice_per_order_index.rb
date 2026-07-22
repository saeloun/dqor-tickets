class AddUniqueInvoicePerOrderIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :invoices, :order_id, unique: true, where: "kind = 'invoice'", name: "index_invoices_on_order_id_where_invoice"
  end
end
