require "rails_helper"

RSpec.describe Invoice, type: :model do
  def order_with_ticket(**attributes)
    order = create(:order, :paid, metadata: { "billing_address" => "Test address", "billing_state_name" => "Test state" }, **attributes)
    create(:ticket, order:)
    order
  end

  it "numbers invoices sequentially within an Indian financial year" do
    first = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 4, 1))
    second = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2027, 3, 31))

    expect(first.number).to eq("TEST/2627/000001")
    expect(second.number).to eq("TEST/2627/000002")
  end

  it "starts a new sequence at the April financial-year boundary" do
    march = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 3, 31))
    april = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 4, 1))

    expect(march.number).to eq("TEST/2526/000001")
    expect(april.number).to eq("TEST/2627/000001")
  end

  it "uses an independent credit-note prefix and reference" do
    order = order_with_ticket
    invoice = described_class.issue_for!(order, issued_on: Date.new(2026, 7, 19))
    credit_note = described_class.issue_for!(
      order,
      kind: :credit_note,
      refers_to: invoice,
      issued_on: Date.new(2026, 7, 20),
      line_items: invoice.line_items
    )

    expect(credit_note.number).to eq("TCN/2627/000001")
    expect(credit_note.refers_to).to eq(invoice)
  end

  it "snapshots buyer and reconciled GST line items" do
    order = order_with_ticket(gstin: "29AAAAA0000A1Z5", billing_state_code: "29")

    invoice = described_class.issue_for!(order, issued_on: Date.new(2026, 7, 19))

    expect(invoice.buyer_snapshot["gstin"]).to eq("29AAAAA0000A1Z5")
    expect(invoice.line_items.sole.values_at("total_paise", "taxable", "igst")).to eq([ 350_000, 296_610, 53_390 ])
  end

  it "cannot be destroyed" do
    invoice = described_class.issue_for!(order_with_ticket)

    expect { invoice.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { invoice.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  def with_invoice_env(values)
    before = ENV.to_h.slice(*values.keys)
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    values.each_key { |key| ENV[key] = before[key] }
  end

  def legacy_invoice(order)
    described_class.insert_all!([ {
      order_id: order.id, number: "DQOR/2026-27/0001", issued_on: Date.new(2026, 7, 19),
      kind: "invoice", buyer_snapshot: described_class.buyer_snapshot(order),
      line_items: described_class.line_item_snapshot(order), created_at: Time.current, updated_at: Time.current
    } ])
    order.invoices.sole
  end

  it "retains an issued legacy number and PDF without requiring current policy" do
    order = order_with_ticket
    invoice = legacy_invoice(order)
    invoice.pdf.attach(io: StringIO.new("%PDF-original"), filename: "original.pdf", content_type: "application/pdf")
    blob_id = invoice.pdf.blob.id
    with_invoice_env("INVOICE_POLICY_VERSION" => nil) do
      expect(described_class.issue_for!(order)).to eq(invoice)
      invoice.attach_pdf!
    end
    expect(invoice.reload.number).to eq("DQOR/2026-27/0001")
    expect(invoice.snapshot_version).to be_nil
    expect(invoice.pdf.blob.id).to eq(blob_id)
    expect(invoice.pdf.download).to eq("%PDF-original")
  end

  it "refuses to reconstruct a missing legacy PDF or credit note from today's facts" do
    order = order_with_ticket
    invoice = legacy_invoice(order)
    expect { invoice.attach_pdf! }.to raise_error(described_class::LegacySnapshotUnavailable)
    expect { described_class.issue_for!(order, kind: :credit_note, refers_to: invoice) }.to raise_error(described_class::LegacySnapshotUnavailable)
    expect(order.invoices.count).to eq(1)
  end

  it "fails closed when policy, reverse charge, seller or series is unconfigured" do
    %w[INVOICE_POLICY_VERSION INVOICE_REVERSE_CHARGE SELLER_GSTIN SELLER_SAC INVOICE_SERIES].each do |key|
      with_invoice_env(key => nil) do
        expect { described_class.issue_for!(order_with_ticket) }.to raise_error(InvoicePolicy::NotConfigured)
      end
    end
    expect(described_class.count).to eq(0)
  end

  it "rejects unsupported seller state, reverse charge and colliding series" do
    [ { "SELLER_GSTIN" => "29AAAAA0000A1Z5" }, { "INVOICE_REVERSE_CHARGE" => "true" }, { "CREDIT_NOTE_SERIES" => "TEST" } ].each do |values|
      with_invoice_env(values) do
        expect { described_class.issue_for!(order_with_ticket) }.to raise_error(InvoicePolicy::NotConfigured)
      end
    end
  end

  it "requires verified address and state details for registered or high-value buyers" do
    order = order_with_ticket(gstin: "29AAAAA0000A1Z5", billing_state_code: "29")
    order.update!(metadata: {})
    expect { described_class.issue_for!(order) }.to raise_error(ActiveRecord::RecordInvalid, /billing_address/)
    order.update!(gstin: nil)
    order.tickets.sole.update!(price_paise: 5_000_000)
    expect { described_class.issue_for!(order) }.to raise_error(ActiveRecord::RecordInvalid, /billing_address/)
  end

  it "renders captured facts and credit notes independently of subsequent buyer and seller edits" do
    order = order_with_ticket
    invoice = described_class.issue_for!(order)
    original_html = ApplicationController.render(template: "pdfs/invoice", locals: { invoice: }, layout: false)
    order.update!(buyer_name: "Changed buyer", metadata: {})
    with_invoice_env("SELLER_NAME" => "Changed seller", "SELLER_ADDRESS" => "Changed address", "SELLER_GSTIN" => nil, "SELLER_SAC" => "123456", "INVOICE_POLICY_VERSION" => nil) do
      html = ApplicationController.render(template: "pdfs/invoice", locals: { invoice: invoice.reload }, layout: false)
      expect(html).to eq(original_html)
      credit = described_class.issue_for!(order, kind: :credit_note, refers_to: invoice)
      expect(credit.buyer_snapshot).to eq(invoice.buyer_snapshot)
      expect(credit.seller_snapshot).to eq(invoice.seller_snapshot)
      expect(credit.tax_snapshot).to eq(invoice.tax_snapshot)
      expect(credit.line_items).to eq(invoice.line_items)
    end
    expect(original_html).to include("Reverse charge: No", "CGST 9%", "SGST 9%", "IGST 0%", "Test address")
  end

  it "rejects changed amounts and cross-order credit references" do
    order = order_with_ticket
    invoice = described_class.issue_for!(order)
    altered = invoice.line_items.deep_dup
    altered.first["total_paise"] += 1
    expect { described_class.issue_for!(order, kind: :credit_note, refers_to: invoice, line_items: altered) }.to raise_error(ArgumentError)
    expect { described_class.issue_for!(order_with_ticket, kind: :credit_note, refers_to: invoice) }.to raise_error(ArgumentError)
    expect { described_class.issue_for!(order_with_ticket, line_items: altered) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects updates, bypass-validation column writes, and in-place JSON edits" do
    invoice = described_class.issue_for!(order_with_ticket)
    expect { invoice.update!(number: "REPLACED") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect { invoice.update_columns(number: "REPLACED") }.to raise_error(ActiveRecord::ActiveRecordError)
    invoice.buyer_snapshot["buyer_name"] = "Changed buyer"
    expect { invoice.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(invoice.reload.buyer_snapshot["buyer_name"]).to eq("Ada Lovelace")
  end

  it "keeps PDF attachment and timestamp updates working for immutable invoices" do
    invoice = described_class.issue_for!(order_with_ticket)
    allow(PdfRenderer).to receive(:render).and_return("%PDF-snapshot")
    invoice.attach_pdf!
    invoice.touch
    invoice.attach_pdf!
    expect(PdfRenderer).to have_received(:render).once
    expect(invoice.reload.pdf.download).to eq("%PDF-snapshot")
  end

  it "allocates all six digits without lexical rollover and stops at exhaustion" do
    prefix = described_class.number_prefix(:invoice, Date.new(2026, 7, 19))
    invoice = described_class.issue_for!(order_with_ticket, issued_on: Date.new(2026, 7, 19))
    # Simulate existing issued serials without invoking the issuer thousands of times.
    described_class.where(id: invoice.id).update_all(number: "#{prefix}009999")
    expect(described_class.next_number(prefix)).to eq("#{prefix}010000")
    described_class.where(id: invoice.id).update_all(number: "#{prefix}999999")
    expect { described_class.next_number(prefix) }.to raise_error(RangeError)
    expect("#{prefix}999999".length).to eq(16)
  end

  it "refuses schema rollback once a versioned document exists" do
    require Rails.root.join("db/migrate/20261002160000_add_versioned_invoice_snapshots")
    described_class.issue_for!(order_with_ticket)
    expect { AddVersionedInvoiceSnapshots.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(described_class.column_names).to include("seller_snapshot", "tax_snapshot", "snapshot_version")
  end

  it "validates credit provenance even for direct model creation" do
    original = described_class.issue_for!(order_with_ticket)
    attributes = original.attributes.except("id", "created_at", "updated_at").merge(
      "number" => "TCN/2627/000001", "kind" => "credit_note", "refers_to_id" => original.id,
      "seller_snapshot" => original.seller_snapshot.merge("name" => "Replacement seller")
    )
    expect { described_class.create!(attributes) }.to raise_error(ActiveRecord::RecordInvalid, /unchanged credit lines/)
  end
end
