# Single source of truth for the event's date, venue, and how far away it is.
# Used by the attendee hub (countdown) and anywhere else that needs the dates.
module Conference
  ZONE             = "Asia/Kolkata".freeze
  START_DATE       = Date.new(2026, 10, 8)
  END_DATE         = Date.new(2026, 10, 11)
  VENUE            = "Hyatt Regency, Pune".freeze
  DATE_RANGE_LABEL = "October 8–11, 2026".freeze

  module_function

  def today
    Time.find_zone!(ZONE).today
  end

  # Whole days from today until the first day of the event (negative once past).
  def days_to_go
    (START_DATE - today).to_i
  end

  def status
    t = today
    return :before if t < START_DATE
    return :during if t <= END_DATE

    :after
  end
end
