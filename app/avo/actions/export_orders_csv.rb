class Avo::Actions::ExportOrdersCsv < Avo::BaseAction
  self.name = "Export orders CSV"

  def handle(query:, **)
    download Order.orders_csv(query), "orders-#{Date.current}.csv"
  end
end
