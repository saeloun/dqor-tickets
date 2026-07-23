class Avo::Actions::EmailOrderLink < Avo::BaseAction
  self.name = "Email order link"
  self.confirmation = false

  def handle(query:, **)
    query.each(&:deliver_order_link!)
    succeed "Order link queued"
  end
end
