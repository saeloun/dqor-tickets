require "rails_helper"

RSpec.describe ConfirmOrderJob, type: :job do
  before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

  def order_with_event(status: :pending, expires_at: 30.minutes.from_now, capacity: 2)
    ticket_type = create(:ticket_type, capacity:)
    order = create(:order, status:, expires_at:, razorpay_order_id: "order_#{SecureRandom.hex(4)}")
    create(:ticket, order:, ticket_type:)
    event = create(:payment_event, order:, kind: "order.paid")
    [ order, event, ticket_type ]
  end

  it "marks the order paid and enqueues confirmation delivery" do
    order, event = order_with_event

    expect { described_class.perform_now(order.razorpay_order_id, event.id) }
      .to have_enqueued_job(DeliverOrderConfirmationJob).with(order)

    expect(order.reload).to be_paid
    expect(order.invoices.invoice.count).to eq(1)
    expect(order.invoices.invoice.sole.pdf).not_to be_attached
  end

  it "renders documents after the payment transaction commits" do
    order, event = order_with_event
    open_transactions = ActiveRecord::Base.connection.open_transactions
    allow(PdfRenderer).to receive(:render) do
      expect(ActiveRecord::Base.connection.open_transactions).to eq(open_transactions)
      "%PDF-1.7 test"
    end

    expect do
      perform_enqueued_jobs(only: DeliverOrderConfirmationJob) do
        described_class.perform_now(order.razorpay_order_id, event.id)
      end
    end.to have_enqueued_mail(OrderMailer, :confirmation)

    expect(order.invoices.invoice.sole.pdf).to be_attached
    expect(order.tickets.sole.pdf).not_to be_attached
  end

  it "is idempotent" do
    order, event = order_with_event

    perform_enqueued_jobs(only: DeliverOrderConfirmationJob) do
      2.times { described_class.perform_now(order.razorpay_order_id, event.id) }
    end

    expect(order.invoices.invoice.count).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(1)
  end

  it "retries a transient failure without duplicating confirmation side effects" do
    order, event = order_with_event
    attempts = 0
    allow_any_instance_of(Order).to receive(:mark_paid!).and_wrap_original do |method, *arguments|
      attempts += 1
      raise Net::OpenTimeout, "timed out" if attempts == 1

      method.call(*arguments)
    end

    perform_enqueued_jobs(only: [ described_class, DeliverOrderConfirmationJob ]) do
      described_class.perform_later(order.razorpay_order_id, event.id)
    end

    expect(attempts).to eq(2)
    expect(order.reload).to be_paid
    expect(order.invoices.invoice.count).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == MailDeliveryJob }).to eq(1)
  end

  it "revives an expired order when stock remains" do
    order, event = order_with_event(status: :expired, expires_at: 1.minute.ago, capacity: 1)

    described_class.perform_now(order.razorpay_order_id, event.id)

    expect(order.reload).to be_paid
    expect(order.invoices.invoice.count).to eq(1)
  end

  it "flags an expired late payment when stock is gone" do
    order, event, ticket_type = order_with_event(status: :expired, expires_at: 1.minute.ago, capacity: 1)
    create(:ticket, ticket_type:, order: create(:order, :paid))

    described_class.perform_now(order.razorpay_order_id, event.id)

    expect(order.reload).to be_expired
    expect(order.metadata).to include("late_payment_requires_refund" => true)
    expect(order.invoices).to be_empty
  end
end
