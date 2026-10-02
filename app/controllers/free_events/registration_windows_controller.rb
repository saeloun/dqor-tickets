class FreeEvents::RegistrationWindowsController < FreeEvents::BaseController
  def show
    load_window
  end

  def update
    @input = params.fetch(:window, ActionController::Parameters.new).permit(:opens_local, :closes_local).to_h if params[:operation] == "save"
    FreeEvents::Windows.change(**access, action: params.expect(:operation), revision: params.expect(:revision), **(@input || {}).symbolize_keys)
    redirect_to free_event_window_path(params[:organization_id], params[:event_id], params[:ticket_type_id]), notice: params[:operation] == "publish" ? "Registration window published." : "Registration window draft saved."
  rescue FreeEvents::Windows::Invalid => error
    @error = error.message
    load_window
    render :show, status: :unprocessable_content
  end

  private
    def access
      { user: current_user, organization_id: params[:organization_id], event_id: params[:event_id], ticket_type_id: params[:ticket_type_id] }
    end

    def load_window
      FreeEvents::Windows.read(**access) { |event, type, window| @event, @ticket_type, @window = event, type, window }
      @preview = FreeEvents::Availability.call(event: @event, ticket_type: @ticket_type, preview: @window)
    end
end
