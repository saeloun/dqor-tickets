module AvoMissingAssociation
  private
    def set_related_resource
      return head(:not_found) unless find_association_field(resource: @resource, association: params[:related_name])

      super
    end
end
