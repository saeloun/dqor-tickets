class Operations::SponsorDeal < Operations::Record
  belongs_to :business_contact, class_name: "Operations::BusinessContact"
  has_many :manual_entries, class_name: "Operations::ManualEntry", dependent: :restrict_with_exception
  validates :title, presence: true, length: { maximum: 200 }
  validates :amount_paise, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 9_000_000_000_000 }
  validates :stage, inclusion: { in: %w[pledged committed] }
  validates :contribution, inclusion: { in: %w[cash in_kind] }
  validate { same_event(business_contact, :business_contact) }

  def cash_received_paise
    manual_entries.where(kind: "receipt").sum(:amount_paise) - manual_entries.where(kind: "refund").sum(:amount_paise)
  end
end
