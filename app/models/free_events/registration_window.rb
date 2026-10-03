class FreeEvents::RegistrationWindow < ApplicationRecord
  self.table_name = "free_registration_windows"
  belongs_to :event
  belongs_to :ticket_type
end
