# Avo 4.1.6 dereferences missing association fields before validating them.
module AvoAssociationGuard
  private

  def set_related_resource
    field = find_association_field(resource: @resource, association: params[:related_name])
    raise ActiveRecord::RecordNotFound unless field.respond_to?(:resource_class)

    super
  end
end

Rails.application.config.to_prepare do
  Avo::AssociationsController.prepend(AvoAssociationGuard)
end
