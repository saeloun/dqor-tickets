class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    types = TicketType.all.to_a
    conference = types.select { |t| !t.requires_conference_pass? && t.price_paise.to_i.positive? && t.purchasable? }
    @conference_from = conference.min_by(&:price_paise)
    @explore_pass = types.find { |t| t.slug == "explore-pune-day" }
  end
end
