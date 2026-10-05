class Organizer::BaseController < ApplicationController
  layout "organizer_platform"
  allow_unauthenticated_access
  prepend_before_action :require_platform
  before_action :require_user
  before_action :set_organization
  helper_method :can_manage_events?

  private
    def require_platform
      head :not_found unless Rails.configuration.x.organizer_platform_enabled
    end

    def set_organization
      @membership = Membership.find_by!(user: current_user, organization_id: params[:organization_id])
      @organization = @membership.organization
    end

    def can_manage_events?
      @membership.manage_events?
    end

    def require_event_manager
      head :forbidden unless can_manage_events?
    end
end
