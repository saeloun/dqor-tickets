class Avo::WallLoveNotesController < Avo::ResourcesController
  before_action :prevent_direct_changes

  private
    def prevent_direct_changes
      head :forbidden unless request.get? || request.head?
    end
end
