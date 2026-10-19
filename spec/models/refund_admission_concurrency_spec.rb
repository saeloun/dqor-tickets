require "rails_helper"
require "timeout"

RSpec.describe "Refund admission concurrency", type: :model do
  self.use_transactional_tests = false

  before do
    @type = create(:ticket_type, price_paise: 450_000)
    @order = create(:order, :paid, total_paise: 550_000)
    @ticket = create(:ticket, order: @order, ticket_type: @type, price_paise: 550_000)
    Invoice.issue_for!(@order)
    create(:payment_event, order: @order, razorpay_payment_id: "pay_concurrent_#{@order.id}")
  end

  after do
    @worker&.join(10)
    @order.invoices.credit_note.delete_all
    @order.invoices.invoice.delete_all
    PaymentEvent.where(order_id: @order.id).delete_all
    Refund.where(order_id: @order.id).delete_all
    @ticket.destroy!
    @order.reload.destroy!
    @type.reload.destroy!
  end

  [ :apply_price_adjustment_refund!, :refund_tickets! ].each do |competing_action|
    it "serializes an adjustment against #{competing_action}" do
      ready = Queue.new
      @order.with_lock do
        @worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.execute("SET lock_timeout = '5s'")
            ready << connection.select_value("SELECT pg_backend_pid()")
            Order.find(@order.id).public_send(competing_action, [ @ticket.id ])
          ensure
            connection.execute("RESET lock_timeout")
          end
        rescue StandardError => error
          error
        end
        pid = Timeout.timeout(5) { ready.pop }
        Timeout.timeout(5) do
          loop do
            break if ActiveRecord::Base.connection.select_value("SELECT cardinality(pg_blocking_pids(#{Integer(pid)}))").positive?
            sleep 0.01
          end
        end
        @order.apply_price_adjustment_refund!([ @ticket.id ])
      end
      expect(Timeout.timeout(10) { @worker.value }).to be_a(Refund::AlreadyRefunded)
      expect(@order.refunds.count).to eq(1)
      expect(@order.refunds.sum(:amount_paise)).to eq(100_000)
    end
  end

  it "commits durable refund jobs with reservations and rolls both back together" do
    previous_adapter = InitiateRefundJob.queue_adapter
    InitiateRefundJob.queue_adapter = :solid_queue
    expect(SolidQueue::Record.connection_pool).to eq(Order.connection_pool)
    original_jobs = SolidQueue::Job.count
    @order.with_lock do
      @order.apply_price_adjustment_refund!([ @ticket.id ])
      expect(SolidQueue::Job.count).to eq(original_jobs + 1)
      raise ActiveRecord::Rollback
    end
    expect(@order.refunds.count).to eq(0)
    expect(SolidQueue::Job.count).to eq(original_jobs)
    @order.apply_price_adjustment_refund!([ @ticket.id ])
    expect(@order.refunds.count).to eq(1)
    expect(SolidQueue::Job.count).to eq(original_jobs + 1)
  ensure
    SolidQueue::Job.where("arguments LIKE ?", "%pay_concurrent%").each(&:destroy!)
    InitiateRefundJob.queue_adapter = previous_adapter
  end
end
