class Avo::Actions::OpenCheckin < Avo::BaseAction
  self.name = "Check in selected tickets"
  self.confirmation = false

  def handle(query:, **)
    return error "Administrator access required" unless Current.admin_user&.admin?

    ids = query.first(CheckinsController::MAX_BATCH_SIZE + 1).map(&:id)
    return error "Select between 1 and #{CheckinsController::MAX_BATCH_SIZE} tickets. Do not select all pages." unless ids.any? && ids.size <= CheckinsController::MAX_BATCH_SIZE

    redirect_to Rails.application.routes.url_helpers.checkin_path(ticket_ids: ids)
  end
end
