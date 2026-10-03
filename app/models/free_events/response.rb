class FreeEvents::Response < ApplicationRecord
  self.table_name = "free_event_responses"
  belongs_to :ticket
  belongs_to :form_version, class_name: "FreeEvents::FormVersion"

  def readonly?
    persisted?
  end
end
