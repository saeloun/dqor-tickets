module FreeEvents::WindowsHelper
  def window_time(value, timezone)
    return "Event end not set" unless value
    value.in_time_zone(timezone).strftime("%a, %-d %b %Y · %-I:%M %p %:z")
  end

  def window_input(value, timezone)
    value&.in_time_zone(timezone)&.strftime("%Y-%m-%dT%H:%M")
  end

  def event_local_range(event)
    start = event.starts_at.in_time_zone(event.timezone)
    finish = event.ends_at.in_time_zone(event.timezone)
    if start.to_date == finish.to_date
      start_format = start.strftime("%p") == finish.strftime("%p") ? "%-I:%M" : "%-I:%M %p"
      "#{start.strftime('%a, %-d %b %Y')} · #{start.strftime(start_format)}–#{finish.strftime('%-I:%M %p')}"
    else
      "#{start.strftime('%a, %-d %b %Y · %-I:%M %p')} – #{finish.strftime('%a, %-d %b %Y · %-I:%M %p')}"
    end
  end

  def registration_state_label(state)
    { upcoming: "Upcoming", available: "Available", sold_out: "Sold out", closed: "Closed" }.fetch(state)
  end
end
