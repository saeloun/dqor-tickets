require "rails_helper"

RSpec.describe InvoicePolicyReview do
  let(:admin) { create(:admin_user) }

  it "allows empty drafts but not configured or approved incomplete facts" do
    review = described_class.create!(created_by: admin)
    expect(review).to be_draft
    expect(review.update(status: :configured)).to be(false)
    expect(review.errors.full_messages.join).to include("seller legal name")
    expect(review.update(status: :approved, approved_by: admin, approved_at: Time.current)).to be(false)
  end

  it "requires configuration before approval and freezes the approved review" do
    review = described_class.create!(created_by: admin, policy_data: finance_policy_facts)
    expect(review.update(status: :approved, approved_by: admin, approved_at: Time.current)).to be(false)
    review.reload.update!(status: :configured, configured_at: Time.current)
    review.update!(status: :approved, approved_by: admin, approved_at: Time.current)
    expect { review.update!(policy_data: finance_policy_facts.merge("seller_name" => "Changed")) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { review.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "cannot configure unsupported rates, seller state or reverse charge" do
    %w[gst_rate seller_gstin reverse_charge].each do |key|
      review = described_class.new(created_by: admin, status: :configured, policy_data: finance_policy_facts.merge(key => "unsupported"))
      expect(review).not_to be_valid
    end
  end

  it "records approval without changing environment or creating any invoice" do
    before_env = ENV.to_h
    expect { approved_finance_policy(admin) }.not_to change(Invoice, :count)
    expect(ENV.to_h).to eq(before_env)
    expect(described_class.last).to be_runtime_matches
  end
end
