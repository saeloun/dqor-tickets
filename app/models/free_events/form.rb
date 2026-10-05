class FreeEvents::Form < ApplicationRecord
  self.table_name = "free_event_forms"
  belongs_to :event
  belongs_to :ticket_type
  has_many :versions, class_name: "FreeEvents::FormVersion", dependent: :restrict_with_exception

  def published_version
    versions.order(number: :desc).first
  end
end
