require "rails_helper"
require "timeout"

RSpec.describe "refund and admission lock ordering", type: :model do
  self.use_transactional_tests = false

  before do
    @type = create(:ticket_type)
    @order = create(:order, :paid, total_paise: 350_000)
    @ticket = create(:ticket, order: @order, ticket_type: @type, price_paise: 350_000)
    @order.update!(metadata: { "invoice_purchase_lines" => Invoice.line_item_snapshot(@order) })
    @refund = create(:refund, order: @order, status: :initiated, ticket_ids: [ @ticket.id ], amount_paise: 350_000)
    @event = create(:payment_event, order: @order, kind: "refund.processed", amount_paise: 350_000)
  end

  after do
    @worker&.join(10)
    Invoice.where(order_id: @order.id).credit_note.delete_all
    Invoice.where(order_id: @order.id).delete_all
    @refund.destroy!
    @event.destroy!
    @ticket.destroy!
    @order.destroy!
    @type.destroy!
  end

  [ false, true ].each do |issued|
    it "rejects admission after the refund commits with an #{issued ? 'issued' : 'pending'} invoice" do
      Invoice.issue_for!(@order) if issued
      ready = Queue.new
      @order.with_lock do
        @refund.process!(@event)
        @worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.execute("SET lock_timeout = '5s'")
            ready << connection.select_value("SELECT pg_backend_pid()")
            ticket = Ticket.find(@ticket.id)
            ticket.order.with_lock { ticket.check_in!(Date.new(2026, 10, 8)) }
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
      end
      expect(Timeout.timeout(10) { @worker.value }).to be_a(Ticket::Canceled)
      expect(@ticket.reload.checked_in_at).to be_empty
      expect(@refund.reload).to be_processed
      expect(@refund.credit_note_pending?).to eq(!issued)
    end

    it "serializes admission with a refund when the original invoice is #{issued ? 'issued' : 'pending'}" do
      Invoice.issue_for!(@order) if issued
      ready = Queue.new
      # Admission in PR146 and slot redemption in PR149 both acquire order before
      # ticket. Hold that same boundary, then wait for the refund to contend on it.
      @order.with_lock do
        @worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            connection.execute("SET lock_timeout = '5s'")
            ready << connection.select_value("SELECT pg_backend_pid()")
            Refund.find(@refund.id).process!(PaymentEvent.find(@event.id))
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
        # Before the fix, refund already owns this ticket while waiting for order:
        # this admission attempt completes the cycle and PostgreSQL aborts one side.
        @ticket.check_in!(Date.new(2026, 10, 8))
      end
      result = Timeout.timeout(10) { @worker.value }
      expect(result).not_to be_a(Exception)
      expect(@refund.reload).to be_processed
      expect(@ticket.reload.canceled_at).to be_present
      expect(@ticket.checked_in_at).to have_key("2026-10-08")
      expect(@refund.credit_note_pending?).to eq(!issued)
      @refund.process!(@event)
      expect(@order.invoices.credit_note.count).to eq(issued ? 1 : 0)
    end
  end
end
