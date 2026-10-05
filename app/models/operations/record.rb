class Operations::Record < ApplicationRecord
  self.abstract_class = true
  belongs_to :event

  private
    def same_event(record, attribute)
      errors.add(attribute, "must belong to this event") if record && record.event_id != event_id
    end
end
