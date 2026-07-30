class Payout < ApplicationRecord
  belongs_to :organizer
  belongs_to :event, optional: true
  has_many :payout_lines, dependent: :destroy

  enum :status, {
    pending: "pending",
    processing: "processing",
    paid: "paid",
    failed: "failed",
    on_hold: "on_hold"
  }, validate: true

  def compute_net!
    self.net_minor = gross_minor - platform_fee_minor - fee_gst_minor - tcs_minor - tds_minor
  end
end
