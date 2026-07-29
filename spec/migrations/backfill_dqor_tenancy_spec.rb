require "rails_helper"
require Rails.root.join("db/migrate/20260729000200_backfill_dqor_tenancy")

RSpec.describe BackfillDqorTenancy do
  it "idempotently scopes every existing DQOR row and reverses the backfill" do
    ticket_type = create(:ticket_type)
    coupon = create(:coupon, ticket_type:)
    order = create(:order, coupon:)
    ticket = create(:ticket, order:, ticket_type:)
    invoice = create(:invoice, order:)
    refund = create(:refund, order:)
    payment_event = create(:payment_event, order:)
    records = [ ticket_type, coupon, order, ticket, invoice, refund, payment_event ]
    migration = described_class.new

    migration.suppress_messages { 2.times { migration.up } }

    expect(Organizer.count).to eq(1)
    expect(Event.count).to eq(1)
    expect(records).to all(satisfy { |record| record.reload.event_id.present? })
    expect(order.reload.organizer_id).to eq(Organizer.sole.id)
    expect(invoice.reload.organizer_id).to eq(Organizer.sole.id)
    expect(InvoiceSequence.sole).to have_attributes(
      organizer_id: Organizer.sole.id,
      series: "invoice",
      fiscal_year: "2026-27",
      last_number: invoice.number.split("/").last.to_i
    )

    migration.suppress_messages { migration.down }

    expect(records).to all(satisfy { |record| record.reload.event_id.nil? })
    expect(order.reload.organizer_id).to be_nil
    expect(invoice.reload.organizer_id).to be_nil
    expect(Organizer.count).to eq(0)
    expect(Event.count).to eq(0)
  end
end
