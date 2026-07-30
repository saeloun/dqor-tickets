class SponsorOrder < ApplicationRecord
  belongs_to :sponsor
  belongs_to :sponsorship_tier, optional: true

  enum :status, {
    pending: "pending",
    invoiced: "invoiced",
    paid: "paid",
    overdue: "overdue",
    cancelled: "cancelled"
  }, validate: true

  validates :amount_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
