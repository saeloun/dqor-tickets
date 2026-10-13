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
    result = Event::DraftImport.call(@event)
    @event = result.event
    case result.status
    when :created, :existing
      notice = result.status == :created ? "Draft created." : "This source is already imported. Existing event retained."
      redirect_to organizer_organization_event_path(@organization, @event), notice: notice
    when :conflict
      render :new, status: :conflict
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
  rescue ActiveRecord::RecordNotUnique
    @event.errors.add(:source_url, "already belongs to another event in this organization")
    render :edit, status: :unprocessable_content
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
      params.expect(event: [ :title, :slug, :starts_at, :ends_at, :timezone, :description, :venue_name, :venue_address, :source_url, :external_registration_url, :cfp_url, :topics, :import_notes ])
    end
end
