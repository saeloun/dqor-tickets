class FreeEvents::RegistrationsController < FreeEvents::BaseController
  rate_limit to: 20, within: 1.minute, only: :create, by: -> { current_user&.id || request.remote_ip }

  def create
    event = Organization.find_by!(slug: params[:organization_slug]).events.published.find_by!(slug: params[:event_slug])
    FreeEvents::Register.call(user: current_user, event_id: event.id, ticket_type_id: params.expect(:ticket_type_id))
    redirect_to free_event_ticket_path(event.organization.slug, event.slug), notice: "You’re registered. Your free ticket is ready."
  rescue FreeEvents::Register::Unavailable => error
    redirect_to published_event_path(params[:organization_slug], params[:event_slug]), alert: error.message
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
end
