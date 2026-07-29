class PayoutLine < ApplicationRecord
  KINDS = %w[sale refund_clawback fee tcs tds adjustment].freeze

  belongs_to :payout
  belongs_to :order, optional: true

  validates :kind, inclusion: { in: KINDS }
end
