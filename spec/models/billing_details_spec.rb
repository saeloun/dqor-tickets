require "rails_helper"

RSpec.describe BillingDetails do
  let(:address) { { billing_address: "12 Example Road", billing_state_name: "Maharashtra", billing_state_code: "27" } }

  it "keeps low-value personal bookings free of mandatory billing fields" do
    expect(described_class.new(total_paise: 4_999_999)).to be_valid
  end

  it "requires address and state at the exact high-value boundary and for registered buyers" do
    [ { total_paise: 5_000_000 }, { total_paise: 100, gstin: "27AAAAA0000A1Z5", gst_legal_name: "Test Buyer" }, { total_paise: 100, requested: "1" } ].each do |facts|
      details = described_class.new(**facts)
      expect(details).not_to be_valid
      expect(details.errors.attribute_names).to include(:billing_address, :billing_state_name, :billing_state_code)
      expect(described_class.new(**facts, **address)).to be_valid
    end
  end

  it "rejects a state conflicting with the supplied GSTIN and partial addresses" do
    expect(described_class.new(**address, gstin: "29AAAAA0000A1Z5", gst_legal_name: "Test Buyer")).not_to be_valid
    expect(described_class.new(billing_address: "Partial address")).not_to be_valid
  end

  it "does not rewrite an issued invoice or captured jurisdiction" do
    order = create(:order, :paid, billing_state_code: "27")
    create(:ticket, order:)
    expect { described_class.update_order!(order, address.merge(billing_state_code: "29"), source: "test", revision: 0) }.to raise_error(BillingDetails::Locked)
    invoice = Invoice.issue_for!(order)
    expect { described_class.update_order!(order, address, source: "test", revision: 0) }.to raise_error(BillingDetails::Locked)
    expect(invoice.reload.buyer_snapshot).not_to have_key("billing_address")
  end

  it "uses a revision guard, audits the actor without copying PII, and preserves unrelated metadata" do
    order = create(:order, metadata: { "discount_paise" => 123 })
    described_class.update_order!(order, address, source: "admin:1", revision: 0)
    expect(order.reload.metadata).to include("billing_revision" => 1, "discount_paise" => 123, "billing_address" => "12 Example Road")
    expect(order.metadata["billing_updates"].sole).to include("source" => "admin:1")
    expect(order.metadata["billing_updates"].to_json).not_to include("12 Example Road")
    expect { described_class.update_order!(order, address, source: "admin:2", revision: 0) }.to raise_error(BillingDetails::Stale)
  end

  it "redacts nested billing metadata from model inspection and request parameter logs" do
    order = create(:order, metadata: { "billing_address" => "Sensitive street", "billing_request_nonce" => "private-nonce" })
    expect(order.inspect).not_to include("Sensitive street", "private-nonce")
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
      "checkout" => { "billing_address" => "Sensitive street", "gstin" => "27AAAAA0000A1Z5" }, "token" => "private-token"
    )
    expect(filtered.to_s).not_to include("Sensitive street", "27AAAAA0000A1Z5", "private-token")
  end
end
