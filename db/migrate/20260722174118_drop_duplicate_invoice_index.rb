class DropDuplicateInvoiceIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :invoices, :order_id, unique: true, where: "kind = 'invoice'", name: "index_invoices_on_order_id_where_invoice"
  end
end
