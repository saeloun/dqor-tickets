class Payment < ApplicationRecord
  belongs_to :order

  enum :status, {
    created: "created",
    authorized: "authorized",
    captured: "captured",
    failed: "failed",
    refunded: "refunded"
  }, validate: true

  validates :gateway, presence: true
end
