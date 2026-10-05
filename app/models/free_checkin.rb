class FreeCheckin < ApplicationRecord
  belongs_to :event
  belongs_to :ticket
  belongs_to :operator, class_name: "User"
end
