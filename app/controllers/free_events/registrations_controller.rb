class FreeEvents::RegistrationsController < FreeEvents::BaseController
  rescue_from FreeEvents::Register::Unavailable do |error|
    redirect_to published_event_path(params[:organization_slug], params[:event_slug]), alert: error.message
  end

  rate_limit to: 20, within: 1.minute, only: :create, by: -> { current_user&.id || request.remote_ip }

  def new
    FreeEvents::Questions::Schema.require_enabled!
    load_registration_form
    render :new, layout: "free_event_registration"
  end

  def create
    event = Organization.find_by!(slug: params[:organization_slug]).events.published.find_by!(slug: params[:event_slug])
    FreeEvents::Register.call(user: current_user, event_id: event.id, ticket_type_id: params.expect(:ticket_type_id), registration_answers: answer_params, form_version_id: params[:form_version_id])
    redirect_to free_event_ticket_path(event.organization.slug, event.slug), notice: "You’re registered. Your free ticket is ready."
  rescue FreeEvents::Questions::Invalid => error
    @errors = error.errors
    @answers = answer_params.is_a?(Hash) ? answer_params : {}
    load_registration_form
    render :new, layout: "free_event_registration", status: :unprocessable_content
  end

  def index
    @orders = Order.paid.where(user_id: current_user.id).where.not(event_id: nil).order(created_at: :desc)
    @events = Event.where(id: @orders.map(&:event_id)).index_by(&:id)
  end

  def show
    @event = Organization.find_by!(slug: params[:organization_slug]).events.published.find_by!(slug: params[:event_slug])
    order = Order.paid.find_by!(event_id: @event.id, user_id: current_user.id)
    @ticket = order.tickets.where(canceled_at: nil).find_by!(event_id: @event.id)
    @checkin = FreeCheckin.find_by(event_id: @event.id, ticket: @ticket)
  end
  private
    def answer_params
      raw = params[:registration_answers]
      raw.is_a?(ActionController::Parameters) ? raw.to_unsafe_h : (raw || {})
    end

    def load_registration_form
      @event = Organization.find_by!(slug: params[:organization_slug]).events.published.find_by!(slug: params[:event_slug])
      @ticket_type = TicketType.where(event_id: @event.id, price_paise: 0).where.not(free_published_at: nil).find(params[:ticket_type_id])
      availability = FreeEvents::Availability.call(event: @event, ticket_type: @ticket_type)
      raise FreeEvents::Register::Unavailable, availability.message unless availability.available?
      @version = FreeEvents::Form.find_by(event_id: @event.id, ticket_type_id: @ticket_type.id)&.published_version
      raise ActiveRecord::RecordNotFound unless @version
      @answers ||= {}
    end
end
