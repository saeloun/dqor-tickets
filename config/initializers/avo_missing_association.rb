Rails.application.config.to_prepare do
  Avo::AssociationsController.prepend(AvoMissingAssociation)
end
