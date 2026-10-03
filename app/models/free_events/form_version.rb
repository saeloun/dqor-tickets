class FreeEvents::FormVersion < ApplicationRecord
  self.table_name = "free_event_form_versions"
  belongs_to :form, class_name: "FreeEvents::Form"

  def readonly?
    persisted?
  end
end
