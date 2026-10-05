class FreeEvents::AttendeesController < FreeEvents::BaseController
  def index
    @rows = FreeEvents::Attendees.rows(**access_arguments)
    @event = Event.find_by!(id: params[:event_id], organization_id: params[:organization_id])
    if request.format.csv?
      send_data FreeEvents::Attendees.csv(**access_arguments), type: "text/csv", filename: "event-attendees.csv"
    end
  end

  def create
    FreeEvents::CheckIn.call(**access_arguments, ticket_id: params.expect(:ticket_id))
    redirect_to free_event_attendees_path(params[:organization_id], params[:event_id]), notice: "Attendee checked in."
  rescue ArgumentError => error
    redirect_to free_event_attendees_path(params[:organization_id], params[:event_id]), alert: error.message
  end

  private
    def access_arguments
      { user: current_user, organization_id: params[:organization_id], event_id: params[:event_id] }
    end
end
