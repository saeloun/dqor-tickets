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
end
