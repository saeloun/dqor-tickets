class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[index]

  before_action :set_event
  skip_before_action :require_authentication, only: %i[create destroy]
  before_action :require_user_authentication, only: %i[create destroy]

  def index
    return head :not_found unless @event.guest_list_public?

    @registrations = @event.registrations.public_guests.includes(:user)
  end

  def create
    registration = @event.registrations.find_or_initialize_by(user: current_user)

    registration.assign_attributes(
      attendance_state: registration_state,
      payment_state: "not_required",
      source: "self"
    )
    registration.save!

    redirect_to event_path(@event.organizer.slug, @event.slug), notice: "You are #{registration.attendance_state}."
  end

  def destroy
    registration = @event.registrations.find_by!(user: current_user)
    registration.update!(attendance_state: "cancelled")
    redirect_to event_path(@event.organizer.slug, @event.slug), notice: "Your registration has been cancelled."
  end

  private
    def set_event
      @event = Event.find_by!(organizer: Organizer.find_by!(slug: params[:organizer_slug]), slug: params[:event_slug])
    end

    def registration_state
      params[:state] == "interested" ? "interested" : "going"
    end
end
