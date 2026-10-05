class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    @ticket_sale_at = Time.current
    types = TicketType.legacy.where(hidden: false).order(:position, :id).to_a
    @available_quantities = types.to_h { |type| [ type.id, type.available_quantity(at: @ticket_sale_at) ] }
    conference = types.select { |type| type.conference_pass? && type.price_paise.positive? }
    @conference_from = conference.select { |type| type.purchasable?(at: @ticket_sale_at) && @available_quantities.fetch(type.id).positive? }.min_by(&:price_paise)
    @conference_pass = @conference_from || conference.find { |type| type.sales_start_at && type.sales_start_at > @ticket_sale_at } ||
      conference.find { |type| type.purchasable?(at: @ticket_sale_at) } || conference.first
    @rails_girls_pass = types.find { |type| type.slug == "rails-girls-pune" }
    @explore_pass = types.find { |type| type.slug == "explore-pune-day" }
  end
end
