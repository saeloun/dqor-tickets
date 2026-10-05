class Organizer::EventsController < Organizer::BaseController
  before_action :require_event_manager, except: %i[index show]
  before_action :set_event, only: %i[show edit update publish]

  def index
    @events = @organization.events.order(created_at: :desc)
  end

  def show
  end

  def new
    @event = @organization.events.new
  end

  def create
    @event = @organization.events.new(event_params)
    if @event.save
      redirect_to organizer_organization_event_path(@organization, @event), notice: "Draft created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to organizer_organization_event_path(@organization, @event), notice: "Event saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def publish
    if @event.update(status: :published)
      redirect_to organizer_organization_event_path(@organization, @event), notice: "Event published."
    else
      render :show, status: :unprocessable_content
    end
  end

  private
    def set_event
      @event = @organization.events.find(params[:id])
    end

    def event_params
      params.expect(event: [ :title, :slug, :starts_at, :ends_at, :timezone ])
    end
end
