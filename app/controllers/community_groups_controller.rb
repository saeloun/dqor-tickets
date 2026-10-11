class CommunityGroupsController < ApplicationController
  layout "community_groups"
  allow_unauthenticated_access
  before_action :require_groups

  def index
    @page = CommunityGroups::PublicCatalog.page_number(params[:page])
    @total = CommunityGroup.published.count
    @groups = CommunityGroup.published.includes(:organization).order(:name, :id).limit(24).offset((@page - 1) * 24)
  end

  def show
    @group = CommunityGroups::PublicCatalog.group(organization_slug: params[:organization_slug], group_slug: params[:group_slug])
    @upcoming = CommunityGroups::PublicCatalog.page(CommunityGroups::PublicCatalog.events(@group, upcoming: true), params[:upcoming_page])
    @past = CommunityGroups::PublicCatalog.page(CommunityGroups::PublicCatalog.events(@group, upcoming: false), params[:past_page])
  end

  private
    def require_groups
      response.headers["Cache-Control"] = "no-store"
      head :not_found unless CommunityGroups::Access.enabled?
    end
end
