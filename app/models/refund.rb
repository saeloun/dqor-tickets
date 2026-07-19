class Refund < ApplicationRecord
  belongs_to :order

  validates :status, presence: true
  validates :amount_paise, numericality: { only_integer: true, greater_than: 0 }
end
