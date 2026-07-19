require "rails_helper"

RSpec.describe ConfirmOrderJob, type: :job do
  def order_with_event(status: :pending, expires_at: 30.minutes.from_now, capacity: 2)
    ticket_type = create(:ticket_type, capacity:)
    order = create(:order, status:, expires_at:, razorpay_order_id: "order_#{SecureRandom.hex(4)}")
    create(:ticket, order:, ticket_type:)
    event = create(:payment_event, order:, kind: "order.paid")
    [ order, event, ticket_type ]
  end

  it "marks the order paid, attaches documents, and enqueues confirmation" do
    order, event = order_with_event

    expect { described_class.perform_now(order.razorpay_order_id, event.id) }
      .to have_enqueued_mail(OrderMailer, :confirmation)

    expect(order.reload).to be_paid
    expect(order.invoices.invoice.sole.pdf).to be_attached
    expect(order.tickets.sole.pdf).to be_attached
  end

  it "is idempotent" do
    order, event = order_with_event

    clear_enqueued_jobs
    2.times { described_class.perform_now(order.razorpay_order_id, event.id) }

    expect(order.invoices.invoice.count).to eq(1)
    expect(enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }).to eq(1)
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
