class InvoiceSequence < ApplicationRecord
  belongs_to :organizer

  enum :series, {
    invoice: "invoice",
    credit_note: "credit_note",
    receipt_voucher: "receipt_voucher",
    commission: "commission"
  }, validate: true

  validates :fiscal_year, presence: true, format: { with: /\A\d{4}-\d{2}\z/ }
  validates :last_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :series, uniqueness: { scope: [ :organizer_id, :fiscal_year ] }
end
