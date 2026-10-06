require "rails_helper"

RSpec.describe "conference capacity concurrency", type: :model do
  self.use_transactional_tests = false

  def clear_inventory
    Invoice.delete_all
    PaymentEvent.delete_all
    Refund.delete_all
    Ticket.delete_all
    Order.delete_all
    Coupon.delete_all
    TicketType.delete_all
  end

  before { clear_inventory }
  after { clear_inventory }
  around { |example| travel_to(Time.zone.local(2026, 10, 6, 18)) { example.run } }

  def type(slug, **attributes)
    create(:ticket_type, slug:, capacity: nil, **attributes)
  end

  def fill_pool(ticket_type)
    order = create(:order, :paid)
    199.times { create(:ticket, order:, ticket_type:) }
  end

  def checkout(ticket_type)
    Orders::Checkout.call(order_attributes: { email: "race@example.test", buyer_name: "Race Buyer" }, items: [ { ticket_type:, quantity: 1 } ])
  end

  def race(*operations)
    connections = Queue.new
    ready = Queue.new
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.execute("SET lock_timeout = '5s'")
          connection.cache do
            expect(ConferenceInventory.available_quantity).to eq(1)
            expect(connection.query_cache.size).to be_positive
            connections << connection.object_id
            ready << true
            start.pop
            begin
              operation.call
            rescue Orders::Checkout::SoldOut, Order::InsufficientAvailability => error
              error
            ensure
              connection.execute("RESET lock_timeout")
            end
          end
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    results = threads.map(&:value)
    expect(operations.size.times.map { connections.pop }.uniq.size).to eq(operations.size)
    expect(ConferenceInventory.available_quantity).to eq(0)
    expect(ConferenceInventory.tickets.where(canceled_at: nil).joins(:order).merge(Order.reserving_inventory).count).to eq(200)
    results
  end

  [ "conference-pass-late-bird", "supporter-pass" ].each do |other_slug|
    it "allows only one regular or #{other_slug} checkout to reserve the last shared seat" do
      regular = type("conference-pass-regular")
      other = type(other_slug)
      fill_pool(regular)
      results = race(-> { checkout(regular) }, -> { checkout(other) })
      expect(results.count { |result| result.is_a?(Order) }).to eq(1)
      expect(results.count { |result| result.is_a?(Orders::Checkout::SoldOut) }).to eq(1)
    end
  end

  it "serializes comp issuance with paid checkout for the last shared seat" do
    regular = type("conference-pass-regular")
    type("complimentary-pass", hidden: true, price_paise: 0)
    fill_pool(regular)
    results = race(-> { checkout(regular) }, -> { Order.issue_comps!(emails: "comp-race@example.test") })
    expect(results.count { |result| result.is_a?(Order) || result.is_a?(Array) }).to eq(1)
    expect(results.count { |result| result.is_a?(Orders::Checkout::SoldOut) || result.is_a?(Order::InsufficientAvailability) }).to eq(1)
  end

  it "serializes late payment reactivation with another tier checkout" do
    regular = type("conference-pass-regular")
    late = type("conference-pass-late-bird")
    expired = create(:order, status: :expired, expires_at: 1.minute.ago)
    create(:ticket, order: expired, ticket_type: late)
    payment = create(:payment_event, order: expired)
    fill_pool(regular)
    results = race(-> { checkout(regular) }, -> { expired.mark_paid!(payment) })
    expect(results.count { |result| result.is_a?(Order) || result == true }).to eq(1)
    expect(results.count { |result| result.is_a?(Orders::Checkout::SoldOut) || result.is_a?(Order::InsufficientAvailability) }).to eq(1)
  end
end
