# Review records never configure ENV or activate issuance.
class InvoicePolicyReview < ApplicationRecord
  self.filter_attributes += [ :policy_data ]
  FIELDS = {
    "seller_name" => "Seller legal name", "seller_address" => "Seller registered address",
    "seller_gstin" => "Seller GSTIN", "seller_sac" => "Service SAC (six digits)",
    "invoice_series" => "Invoice series", "credit_note_series" => "Credit-note series",
    "gst_rate" => "Total GST rate (%)", "cgst_rate" => "CGST rate (%)",
    "sgst_rate" => "SGST rate (%)", "igst_rate" => "IGST rate (%)",
    "reverse_charge" => "Reverse charge", "place_of_supply_policy" => "Place-of-supply policy",
    "review_notes" => "Policy basis and finance review notes"
  }.freeze

  belongs_to :created_by, class_name: "AdminUser"
  belongs_to :approved_by, class_name: "AdminUser", optional: true
  belongs_to :supersedes, class_name: "InvoicePolicyReview", optional: true
  enum :status, { draft: "draft", configured: "configured", approved: "approved" }, validate: true

  validate :complete_supported_policy, unless: :draft?
  validate :review_state
  validate do
    errors.add(:policy_data, "contains unsupported fields") unless policy_data.is_a?(Hash) && (policy_data.keys - FIELDS.keys).empty?
    errors.add(:policy_data, "fields must be text of at most 2000 characters") if policy_data.is_a?(Hash) && policy_data.values.any? { |value| !value.is_a?(String) || value.length > 2000 }
  end

  def readonly?
    persisted? && status_in_database == "approved"
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "approved policy reviews cannot be deleted" if approved?
    super
  end

  def runtime_matches?
    return false unless approved?
    policy = InvoicePolicy.snapshot
    seller = policy.fetch(:seller)
    %w[name address gstin sac].all? { |key| seller[key] == policy_data["seller_#{key}"] } &&
      InvoicePolicy.series(:invoice) == policy_data["invoice_series"] &&
      InvoicePolicy.series(:credit_note) == policy_data["credit_note_series"]
  rescue InvoicePolicy::NotConfigured
    false
  end

  private
    def complete_supported_policy
      return unless policy_data.is_a?(Hash)

      FIELDS.each do |key, label|
        errors.add(:policy_data, "requires #{label.downcase}") if policy_data[key].blank?
      end
      checks = {
        "seller_gstin" => /\A27[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[A-Z0-9]\z/,
        "seller_sac" => /\A\d{6}\z/, "invoice_series" => /\A[A-Z0-9]{1,4}\z/,
        "credit_note_series" => /\A[A-Z0-9]{1,4}\z/
      }
      checks.each { |key, pattern| errors.add(:policy_data, "has an unsupported #{key.humanize.downcase}") unless policy_data[key].to_s.match?(pattern) }
      errors.add(:policy_data, "requires distinct invoice and credit series") if policy_data["invoice_series"] == policy_data["credit_note_series"]
      { "gst_rate" => "18", "cgst_rate" => "9", "sgst_rate" => "9", "igst_rate" => "18", "reverse_charge" => "false", "place_of_supply_policy" => "domestic-18-v1" }.each do |key, value|
        errors.add(:policy_data, "#{key.humanize.downcase} is unsupported by the existing calculator") unless policy_data[key] == value
      end
    end

    def review_state
      if approved?
        errors.add(:status, "must be configured before approval") unless status_in_database == "configured" || status_in_database == "approved"
        errors.add(:approved_by, "must be an administrator") unless approved_by&.admin?
        errors.add(:approved_at, "is required") unless approved_at
      elsif approved_by_id.present? || approved_at.present?
        errors.add(:status, "cannot carry approval while unapproved")
      end
    end
end
