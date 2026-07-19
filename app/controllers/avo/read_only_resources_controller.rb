class Avo::ReadOnlyResourcesController < Avo::ResourcesController
  before_action :reject_writes, only: %i[new create edit update destroy]

  private
    def reject_writes
      head :method_not_allowed
    end
end
