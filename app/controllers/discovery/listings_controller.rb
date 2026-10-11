class Discovery::ListingsController < ApplicationController
  layout "event_discovery"
  allow_unauthenticated_access
  before_action :require_discovery

  def index
    result = Discovery::Catalog.call(params)
    @filters, @period_counts, @total, @page, @listings, @source_count = result.filters, result.period_counts, result.total, result.page, result.listings, result.source_count
  end

  def show
    @listing = Discovery::Listing.includes(:primary_source, references: :source).find(params[:id])
  end

  private
    def require_discovery
      response.headers["Cache-Control"] = "no-store"
      head :not_found unless Rails.configuration.x.event_discovery_enabled
    end
end
