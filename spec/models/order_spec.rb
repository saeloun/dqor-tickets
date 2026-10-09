require "rails_helper"

RSpec.describe Order, type: :model do
  describe ".generate_code" do
    it "uses the eight-character public alphabet" do
      codes = Array.new(25) { described_class.generate_code }

      expect(codes).to all(match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ379]{8}\z/))
      expect(codes.uniq.size).to eq(25)
    end

    it "retries a code already in the database" do
      create(:order, code: "AAAAAAAA")
      allow(SecureRandom).to receive(:random_number).and_return(*Array.new(8, 0), *Array.new(8, 1))

      expect(described_class.generate_code).to eq("BBBBBBBB")
    end
  end

  describe ".expire_overdue!" do
    it "expires only overdue pending orders" do
      overdue = create(:order, expires_at: 1.minute.ago)
      current = create(:order, expires_at: 1.minute.from_now)
      paid = create(:order, :paid, expires_at: 1.minute.ago)

      expect(described_class.expire_overdue!).to eq(1)
      expect(overdue.reload).to be_expired
      expect(current.reload).to be_pending
      expect(paid.reload).to be_paid
    end
  end

  describe "#mark_paid!" do
    it "is idempotent" do
      order = create(:order)
      create(:ticket, order:)
      payment_event = create(:payment_event, order:)

      2.times { order.mark_paid!(payment_event) }

      expect(order.reload).to be_paid
      expect(order.invoices.invoice.count).to eq(1)
    end

    it "rejects a payment event from another order" do
      order = create(:order)
      payment_event = create(:payment_event)

      expect { order.mark_paid!(payment_event) }.to raise_error(ArgumentError)
    end
  end

  describe ".issue_comps!" do
    it "creates and confirms one complimentary order per email" do
      create(:ticket_type, name: "Complimentary Pass", slug: "complimentary-pass", hidden: true, price_paise: 0, capacity: nil)

      expect do
        described_class.issue_comps!(emails: "ada@example.com\ngrace@example.com", attendee_names: "Ada\nGrace")
      end.to have_enqueued_job(DeliverOrderConfirmationJob).twice

      expect(described_class.last(2)).to all(be_paid)
      expect(described_class.last(2).map { |order| order.tickets.sole.attendee_name }).to eq(%w[Ada Grace])
    end
  end

  describe "#refund_tickets!" do
    before { allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test") }

    it "initiates a Razorpay refund for selected invoice lines" do
      order = create(:order, :paid)
      selected = create(:ticket, order:)
      untouched = create(:ticket, order:)
      Invoice.issue_for!(order)
      create(:payment_event, order:, razorpay_payment_id: "pay_test")
      stub_request(:get, "https://api.razorpay.com/v1/payments/pay_test").to_return(
        status: 200,
        body: { entity: "payment", id: "pay_test" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      stub_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund").to_return(
        status: 200,
        body: { entity: "refund", id: "rfnd_test", amount: selected.price_paise }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      refund = nil
      perform_enqueued_jobs(only: InitiateRefundJob) do
        refund = order.refund_tickets!([ selected.id ])
      end

      expect(refund.reload).to have_attributes(status: "initiated", amount_paise: selected.price_paise, razorpay_refund_id: "rfnd_test", ticket_ids: [ selected.id ])
      expect(order.payment_events.find_by(kind: "refund_created")).to have_attributes(amount_paise: selected.price_paise, level: "info", mode: "test")
      expect(selected.reload.canceled_at).to be_nil
      expect(untouched.reload.canceled_at).to be_nil
      expect(a_request(:post, "https://api.razorpay.com/v1/payments/pay_test/refund").with(
        body: hash_including("amount" => selected.price_paise.to_s),
        headers: { "X-Refund-Idempotency" => "dqor-refund-#{refund.id}" }
      )).to have_been_made.once
    end

    it "immediately completes a free-ticket refund without Razorpay" do
      order = create(:order, :paid, total_paise: 0)
      ticket_type = create(:ticket_type, price_paise: 0)
      ticket = create(:ticket, order:, ticket_type:, price_paise: 0)
      Invoice.issue_for!(order)

      refund = order.refund_tickets!([ ticket.id ])

      expect(refund.reload).to have_attributes(status: "processed", amount_paise: 0)
      expect(ticket.reload.canceled_at).to be_present
      expect(order.invoices.credit_note.sole.pdf).to be_attached
      expect(a_request(:any, /api\.razorpay\.com/)).not_to have_been_made
    end
  end

  describe "CSV exports" do
    it "exports buyer, GST, coupon, and attendee details" do
      ticket_type = create(:ticket_type, name: "Regular")
      coupon = create(:coupon, ticket_type: nil, code: "TEAM10", percent: 10, discount_paise: nil)
      order = create(:order, :paid, coupon:, gstin: "27AAAAA0000A1Z5", billing_state_code: "27", metadata: { "discount_paise" => 35_000 })
      create(:ticket, order:, ticket_type:, tshirt_size: "M", dietary_preference: "Vegan")

      expect(described_class.orders_csv(described_class.where(id: order.id))).to include("TEAM10", "Vegan", "cgst_paise")
      expect(described_class.attendees_csv(described_class.where(id: order.id))).to include("Regular", "M", "attendee_email")
    end

    it "exports who needs childcare so the day care can be planned" do
      order = create(:order, :paid)
      create(:ticket, order:, attendee_name: "Needs care", childcare_needed: true)
      create(:ticket, order:, attendee_name: "No care", childcare_needed: false)

      attendees = CSV.parse(described_class.attendees_csv(described_class.where(id: order.id)), headers: true)
      expect(attendees.headers).to include("childcare_needed")
      expect(attendees.map { |row| [ row["attendee_name"], row["childcare_needed"] ] })
        .to match_array([ [ "Needs care", "true" ], [ "No care", "false" ] ])

      orders = CSV.parse(described_class.orders_csv(described_class.where(id: order.id)), headers: true)
      expect(orders.first.fetch("childcare_count")).to eq("1")
    end
  end

  describe "#resend_confirmation!" do
    it "queues another confirmation" do
      order = create(:order, :paid)
      create(:ticket, order:)
      Invoice.issue_for!(order)
      allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")

      expect { order.resend_confirmation! }.to have_enqueued_mail(OrderMailer, :confirmation)
    end
  end

  describe "#deliver_confirmation!" do
    it "does not claim delivery until the mail job is enqueued" do
      order = create(:order, :paid)
      create(:ticket, order:)
      Invoice.issue_for!(order)
      allow(PdfRenderer).to receive(:render).and_return("%PDF-1.7 test")
      attempts = 0
      queue_adapter = MailDeliveryJob.queue_adapter
      allow(queue_adapter).to receive(:enqueue).and_wrap_original do |method, *arguments|
        attempts += 1
        raise ActiveRecord::StatementInvalid, "database is busy" if attempts == 1

        method.call(*arguments)
      end

      expect { order.deliver_confirmation! }.to raise_error(ActiveRecord::StatementInvalid)
      expect(order.reload.metadata).not_to include("confirmation_enqueued_at")

      expect { order.deliver_confirmation! }.to have_enqueued_mail(OrderMailer, :confirmation).once
      expect(order.reload.metadata).to include("confirmation_enqueued_at")
    end
  end
end
