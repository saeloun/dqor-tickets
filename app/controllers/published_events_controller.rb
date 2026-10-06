class PublishedEventsController < ApplicationController
  layout "free_event_public"
  allow_unauthenticated_access
  prepend_before_action :require_platform

  prepend_before_action :uncached_response
  before_action :set_event

  def show
    @free_types = FreeEvents::Access.enabled? ? TicketType.where(event_id: @event.id, price_paise: 0).where.not(free_published_at: nil) : []
    setting = EventWebsiteSetting.find_by(event_id: @event.id)
    if setting&.published
      @configuration = EventWebsites::Configuration.new(setting.published)
      render "event_websites/show", layout: "event_website"
    end
  end

  def website_asset
    raise ActiveRecord::RecordNotFound unless params[:asset_id].to_s.match?(/\A[1-9]\d{0,18}\z/) && params[:asset_id].to_i <= 9_223_372_036_854_775_807
    setting = EventWebsiteSetting.find_by!(event_id: @event.id)
    raise ActiveRecord::RecordNotFound unless setting.published && EventWebsites::Configuration.new(setting.published).asset_ids.include?(params[:asset_id].to_i)
    image = setting.assets.find(params[:asset_id])
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data image.image_data, type: image.content_type, disposition: "inline", filename: "event-website-#{image.id}.webp"
  end

  private
    def uncached_response
      response.headers["Cache-Control"] = "no-store"
    end

    def set_event
      organization = Organization.find_by!(slug: params[:organization_slug])
      @event = organization.events.published.find_by!(slug: params[:event_slug])
    end

    def require_platform
      head :not_found unless Rails.configuration.x.organizer_platform_enabled
    end
end
