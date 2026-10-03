class Operations::FulfillmentTask < Operations::Record
  belongs_to :sponsor_deal, class_name: "Operations::SponsorDeal"
  validates :title, presence: true, length: { maximum: 200 }
  validate { same_event(sponsor_deal, :sponsor_deal) }
end
