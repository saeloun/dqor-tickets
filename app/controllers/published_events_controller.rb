class PublishedEventsController < ApplicationController
  layout "organizer_platform"
  allow_unauthenticated_access
  prepend_before_action :require_platform

  def show
    organization = Organization.find_by!(slug: params[:organization_slug])
    @event = organization.events.published.find_by!(slug: params[:event_slug])
    @free_types = FreeEvents::Access.enabled? ? TicketType.where(event_id: @event.id, price_paise: 0).where.not(free_published_at: nil) : []
  end

  private
    def require_platform
      head :not_found unless Rails.configuration.x.organizer_platform_enabled
    end
end
