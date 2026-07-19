require "rails_helper"

RSpec.describe "checkout concurrency", type: :model do
  self.use_transactional_tests = false

  before do
    Invoice.delete_all
    PaymentEvent.delete_all
    Refund.delete_all
    Ticket.delete_all
    Order.delete_all
    Coupon.delete_all
    TicketType.delete_all
  end

  after do
    Ticket.delete_all
    Order.delete_all
    Coupon.delete_all
    TicketType.delete_all
  end

  it "lets only one checkout reserve the last seat", :aggregate_failures do
    ticket_type = TicketType.create!(name: "Last Seat", slug: "last-seat", price_paise: 100, capacity: 1)
    ready = Queue.new
    start = Queue.new

    threads = 2.times.map do |number|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Orders::Checkout.call(
            order_attributes: { email: "buyer#{number}@example.com", buyer_name: "Buyer #{number}" },
            items: [ { ticket_type_id: ticket_type.id, quantity: 1 } ]
          )
        rescue Orders::Checkout::SoldOut => error
          error
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    expect(results.count { |result| result.is_a?(Order) }).to eq(1)
    expect(results.count { |result| result.is_a?(Orders::Checkout::SoldOut) }).to eq(1)
    expect(Ticket.count).to eq(1)
  end
end
