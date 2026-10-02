# The live DQOR entry points must never consume organizer-owned commerce.
# Explicit scopes are used at each query boundary; this is not a default scope.
module LegacyCommerce
  def self.assert!(record)
    owner = record.respond_to?(:event_id) ? record : record.order
    raise ActiveRecord::RecordNotFound, "Legacy commerce record not found" if owner.event_id.present?
    record
  end
end
