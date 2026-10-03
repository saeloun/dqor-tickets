require "rails_helper"

RSpec.describe "Order pending confirmation concurrency", type: :model do
  self.use_transactional_tests = false

  it "enqueues one pending confirmation across separate database connections" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:)
    ticket_type = ticket.ticket_type
    snapshot = Invoice.line_item_snapshot(order)
    order.update!(metadata: { "invoice_purchase_lines" => snapshot })
    ready = Queue.new
    start = Queue.new
    connections = Queue.new

    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connections << connection.object_id
          ready << true
          start.pop
          Order.find(order.id).deliver_confirmation!(documents_pending: true)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = workers.map(&:value)

    expect(2.times.map { connections.pop }.uniq.size).to eq(2)
    expect(results.count(true)).to eq(1)
    expect(results.count(false)).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(1)
    expect(order.reload.metadata).to include("confirmation_documents_pending" => true, "invoice_purchase_lines" => snapshot)
    expect(order.invoices).to be_empty
  ensure
    workers&.each { |worker| worker.join }
    Ticket.where(order_id: order&.id).delete_all if order
    Order.where(id: order&.id).delete_all if order
    TicketType.where(id: ticket_type&.id).delete_all if ticket_type
  end
end
