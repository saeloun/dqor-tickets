class Avo::Resources::TicketType < Avo::BaseResource
  self.title = :name

  def fields
    field :id, as: :id
    field :name, as: :text, sortable: true
    field :slug, as: :text
    field :description, as: :textarea
    field :price_paise, as: :number, sortable: true
    field :capacity, as: :number
    field :min_per_order, as: :number
    field :max_per_order, as: :number
    field :sales_start_at, as: :date_time
    field :sales_end_at, as: :date_time
    field :hidden, as: :boolean
    field :active, as: :boolean
    field :requires_conference_pass, as: :boolean
    field :position, as: :number
    field :tickets, as: :has_many
    field :coupons, as: :has_many
  end

  def actions
    action Avo::Actions::IssueCompTickets
  end
end
