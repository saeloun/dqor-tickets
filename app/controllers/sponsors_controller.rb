class SponsorsController < ApplicationController
  allow_unauthenticated_access

  def index
    @sponsors_by_tier = Sponsor.published.ordered.group_by(&:tier_label)
  end
end
