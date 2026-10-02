class FreeEvents::InventoryController < FreeEvents::BaseController
  def new
    FreeEvents::Access.with_manager(user: current_user, organization_id: params[:organization_id], event_id: params[:event_id]) { |event| @event = event }
  end

  def create
    @fields = fields = params.expect(ticket_type: [ :name, :capacity ])
    FreeEvents::Inventory.publish!(user: current_user, organization_id: params[:organization_id], event_id: params[:event_id], **fields.to_h.symbolize_keys)
    redirect_to organizer_organization_event_path(params[:organization_id], params[:event_id]), notice: "Free registration is open."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    @error = error.message
    new
    render :new, status: :unprocessable_content
  end
end
