module Finance::DocumentsHelper
  def document_pending_description(reason)
    {
      "InvoicePolicy::NotConfigured" => "Seller policy configuration needs review",
      "ActiveRecord::RecordInvalid" => "Required invoice facts are incomplete or inconsistent",
      "Invoice::LegacySnapshotUnavailable" => "Original seller facts were not captured; locate the archived document",
      "RangeError" => "The approved number series is exhausted; finance must approve a new series",
      "InvoiceMissing" => "The original invoice is still pending",
      "PurchaseLinesMismatch" => "Refund amounts need reconciliation with the original invoice"
    }.fetch(reason, reason.present? ? "Accounting review required" : "No blocker recorded")
  end
end
