class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[show]

  def show
    @event = Event.find_by!(
      organizer: Organizer.find_by!(slug: params[:organizer_slug]),
      slug: params[:event_slug]
    )
    Current.organizer = @event.organizer
    Current.event = @event
    @registration = current_user&.registrations&.find_by(event: @event)
  end
end
