class Api::Public::V1::CommunitiesController < ApplicationController
  allow_unauthenticated_access
  before_action :require_groups

  def index
    page = CommunityGroups::PublicCatalog.page_number(params[:page])
    groups = CommunityGroup.published.includes(:organization).order(:name, :id).limit(24).offset((page - 1) * 24)
    render json: { schema_version: 1, ownership: "tenant_owned_community", page: page, per_page: 24, total: CommunityGroup.published.count, groups: groups.map { |group| CommunityGroups::PublicCatalog.serialize(group) } }
  end

  def show
    group = CommunityGroups::PublicCatalog.group(organization_slug: params[:organization_slug], group_slug: params[:group_slug])
    upcoming = CommunityGroups::PublicCatalog.page(CommunityGroups::PublicCatalog.events(group, upcoming: true), params[:upcoming_page])
    past = CommunityGroups::PublicCatalog.page(CommunityGroups::PublicCatalog.events(group, upcoming: false), params[:past_page])
    render json: { schema_version: 1, group: CommunityGroups::PublicCatalog.serialize(group), upcoming_events: serialize_events(upcoming.records), past_events: serialize_events(past.records), pagination: { upcoming: { page: upcoming.page, total: upcoming.total, per_page: 24 }, past: { page: past.page, total: past.total, per_page: 24 } } }
  end

  private
    def require_groups
      response.headers["Cache-Control"] = "no-store"
      head :not_found unless CommunityGroups::Access.enabled?
    end

    def serialize_events(events)
      events.map do |event|
        event.attributes.slice("title", "slug", "starts_at", "ends_at", "timezone").merge("id" => "hosted-event-#{event.id}", "ownership" => "hosted_event", "details_path" => published_event_path(event.organization.slug, event.slug))
      end
    end
end
