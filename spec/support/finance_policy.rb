module FinancePolicyHelpers
  def finance_policy_facts
    {
      "seller_name" => "Saeloun Software Pvt Ltd", "seller_address" => "Pune, Maharashtra",
      "seller_gstin" => "27AAAAA0000A1Z5", "seller_sac" => "998596",
      "invoice_series" => "TEST", "credit_note_series" => "TCN", "gst_rate" => "18",
      "cgst_rate" => "9", "sgst_rate" => "9", "igst_rate" => "18", "reverse_charge" => "false",
      "place_of_supply_policy" => "domestic-18-v1", "review_notes" => "Synthetic policy reviewed for tests only"
    }
  end

  def approved_finance_policy(admin)
    review = InvoicePolicyReview.create!(created_by: admin, policy_data: finance_policy_facts)
    review.update!(status: :configured, configured_at: Time.current)
    review.update!(status: :approved, approved_by: admin, approved_at: Time.current)
    review
  end
end
RSpec.configure { |config| config.include FinancePolicyHelpers }
