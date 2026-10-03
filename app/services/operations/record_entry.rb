class Operations::RecordEntry
  # Serialize installments/refunds on their parent so concurrent requests cannot
  # exceed a commitment or refund more than recorded cash. Audit is atomic.
  def self.call(entry, user:)
    target = entry.sponsor_deal || entry.vendor_engagement
    return false unless entry.valid?

    target.with_lock do
      balance = entry.sponsor_deal ? target.cash_received_paise : target.cash_paid_paise
      refund = %w[refund expense_refund].include?(entry.kind)
      available = refund ? balance : target.amount_paise - balance
      if entry.amount_paise > available
        entry.errors.add(:amount_paise, "exceeds the remaining commitment or refundable cash")
        return false
      end
      entry.save!
      Operations::AuditLog.create!(event: entry.event, user: user, action: "create", record_kind: "manual_entry", record_id: entry.id)
    end
    true
  end
end
