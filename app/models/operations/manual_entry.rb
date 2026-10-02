# Append-only manual cash records. Corrections use explicit refund entries.
class Operations::ManualEntry < Operations::Record
  belongs_to :sponsor_deal, class_name: "Operations::SponsorDeal", optional: true
  belongs_to :vendor_engagement, class_name: "Operations::VendorEngagement", optional: true
  validates :amount_paise, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 9_000_000_000_000 }
  validates :occurred_on, :reference, presence: true
  validates :reference, length: { maximum: 200 }
  validates :kind, inclusion: { in: %w[receipt refund expense expense_refund] }
  validate :valid_target

  def readonly?
    persisted?
  end

  private
    def valid_target
      same_event(sponsor_deal, :sponsor_deal)
      same_event(vendor_engagement, :vendor_engagement)
      if %w[receipt refund].include?(kind)
        errors.add(:base, "Choose one committed cash sponsor deal") unless sponsor_deal && !vendor_engagement && sponsor_deal.contribution == "cash" && sponsor_deal.stage == "committed"
      elsif %w[expense expense_refund].include?(kind)
        errors.add(:base, "Choose one vendor engagement") unless vendor_engagement && !sponsor_deal
      end
    end
end
