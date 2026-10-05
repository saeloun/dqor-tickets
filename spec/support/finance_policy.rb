module FinancePolicyHelpers
  def finance_policy_facts
    JSON.parse(Rails.root.join("spec/fixtures/synthetic_invoice_policy.json").read)
  end

  def approved_finance_policy(admin)
    review = InvoicePolicyReview.create!(created_by: admin, policy_data: finance_policy_facts)
    review.update!(status: :configured, configured_at: Time.current)
    review.update!(status: :approved, approved_by: admin, approved_at: Time.current)
    review
  end
end
RSpec.configure { |config| config.include FinancePolicyHelpers }
