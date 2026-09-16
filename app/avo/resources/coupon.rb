class Avo::Resources::Coupon < Avo::BaseResource
  self.title = :code

  def fields
    field :id, as: :id
    field :code, as: :text, sortable: true
    field :percent, as: :number
    field :discount_paise, as: :number, help: "Amount in paise (₹500 = 50000). Leave blank when using percent."
    field :max_uses, as: :number, help: "Leave blank for unlimited uses."
    field :uses_count, as: :number, readonly: true, help: "Updated automatically after each paid order."
    field :ticket_type, as: :belongs_to
    field :valid_from, as: :date_time
    field :valid_until, as: :date_time
    field :active, as: :boolean
    field :orders, as: :has_many
  end
end
