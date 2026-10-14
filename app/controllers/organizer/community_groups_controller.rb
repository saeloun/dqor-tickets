class Organizer::CommunityGroupsController < FreeEvents::BaseController
  prepend_before_action :require_groups
  before_action :set_organization
  before_action :require_group_manager, except: %i[index show]
  before_action :set_group, only: %i[show edit]
  helper_method :can_manage_groups?

  def index
    @groups = @organization.community_groups.order(:name, :id)
  end

  def show
    @events = @group.events.order(:starts_at, :id)
    @available_events = @organization.events.where(community_group_id: nil).order(:title, :id)
  end

  def new
    @group = @organization.community_groups.new
  end

  def create
    CommunityGroups::Access.with_manager(user: current_user, organization_id: @organization.id) do |organization|
      @group = organization.community_groups.new(group_params)
      @group.save!
    end
    redirect_to organizer_organization_group_path(@organization, @group), notice: "Community draft created."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
  end

  def update
    with_group { @group.update!(group_params) }
    redirect_to organizer_organization_group_path(@organization, @group), notice: "Community saved."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def publish
    with_group { @group.update!(status: :published) }
    redirect_to organizer_organization_group_path(@organization, @group), notice: "Community published."
  rescue ActiveRecord::RecordInvalid
    @group.status = @group.status_in_database
    show
    render :show, status: :unprocessable_content
  end

  def unpublish
    with_group { @group.update!(status: :draft) }
    redirect_to organizer_organization_group_path(@organization, @group), notice: "Community is now private. Its event publication settings are unchanged."
  end

  def add_event
    CommunityGroups::Access.attach_event(user: current_user, organization_id: @organization.id, group_id: params[:id], event_id: params.require(:event_id))
    redirect_to organizer_organization_group_path(@organization, params[:id]), notice: "Event added to this community."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to organizer_organization_group_path(@organization, params[:id]), alert: error.record.errors.full_messages.to_sentence
  end

  private
    def require_groups
      head :not_found unless CommunityGroups::Access.enabled?
    end

    def set_organization
      @membership = Membership.find_by!(user: current_user, organization_id: params[:organization_id])
      @organization = @membership.organization
    end

    def can_manage_groups?
      @membership.owner? || @membership.admin?
    end

    def require_group_manager
      head :forbidden unless can_manage_groups?
    end

    def set_group
      @group = @organization.community_groups.find(params[:id])
    end

    def with_group
      CommunityGroups::Access.with_manager(user: current_user, organization_id: @organization.id) do |organization|
        @group = organization.community_groups.lock.find(params[:id])
        yield
      end
    end

    def group_params
      params.expect(community_group: [ :name, :slug, :tagline, :description, :city, :country_code, :timezone ])
    end
end
