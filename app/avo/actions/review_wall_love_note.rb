class Avo::Actions::ReviewWallLoveNote < Avo::BaseAction
  self.name = "Review publication"
  self.confirmation = false

  def handle(query:, **)
    return error "Administrator access required" unless Current.admin_user&.admin?
    notes = query.first(2)
    return error "Select one note to review." unless notes.size == 1

    redirect_to Rails.application.routes.url_helpers.wall_love_review_path(notes.first)
  end
end
