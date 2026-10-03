class FreeEvents::OrganizationsController < FreeEvents::BaseController
  rate_limit to: 5, within: 1.hour, only: :create, by: -> { current_user&.id || request.remote_ip }

  def index
    @organizations = Organization.joins(:memberships).where(memberships: { user_id: current_user.id })
  end

  def new
    @organization = Organization.new
  end

  def create
    @organization = Organization.new(params.expect(organization: [ :name, :slug ]))
    Organization.transaction do
      @organization.save!
      Membership.create!(organization: @organization, user: current_user, role: :owner)
    end
    redirect_to organizer_organization_events_path(@organization)
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end
end
