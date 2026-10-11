class Api::Public::V1::DiscoveryController < ApplicationController
  allow_unauthenticated_access
  before_action :require_discovery

  def index
    result = Discovery::Catalog.call(params)
    render json: {
      schema_version: 1, ownership: "external_discovery", local_rsvp_enabled: false,
      filters: result.filters, total: result.total, page: result.page, per_page: 24, counts: result.period_counts,
      events: result.listings.map { |listing| serialize(listing) }
    }
  end

  private
    def require_discovery
      head :not_found unless Rails.configuration.x.event_discovery_enabled
    end

    def serialize(listing)
      listing.attributes.slice("title", "canonical_url", "registration_url", "city", "country_code", "format", "topics", "status", "date_precision", "date_year", "date_month", "starts_on", "ends_on", "starts_at", "ends_at", "timezone", "local_start_time", "local_end_time", "occurrence_dates", "review_state", "review_reason").merge(
        "canonical_url" => Discovery::CanonicalUrl.safe(listing.canonical_url), "registration_url" => Discovery::CanonicalUrl.safe(listing.registration_url),
        "id" => "discovery-#{listing.id}", "ownership" => "external_discovery", "local_rsvp_enabled" => false,
        "sources" => listing.references.map { |reference| { name: reference.source.name, url: Discovery::CanonicalUrl.safe(reference.source_url), revision: reference.revision, fetched_at: reference.last_seen_at, stale: reference.stale? } }
      )
    end
end
