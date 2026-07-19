class Avo::Resources::Coupon < Avo::BaseResource
  self.title = :code

  def fields
    field :id, as: :id
    field :code, as: :text, sortable: true
    field :percent, as: :number
    field :discount_paise, as: :number
    field :max_uses, as: :number
    field :uses_count, as: :number
    field :ticket_type, as: :belongs_to
    field :valid_from, as: :date_time
    field :valid_until, as: :date_time
    field :active, as: :boolean
    field :orders, as: :has_many
  end
end
