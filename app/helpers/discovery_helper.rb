module DiscoveryHelper
  def discovery_external_url(value)
    Discovery::CanonicalUrl.safe(value)
  end

  def discovery_date(listing)
    if listing.occurrence_dates.any?
      return listing.occurrence_dates.map { |date| date.strftime("%-d %b %Y") }.join(" · ") + " · Separate published event days"
    end
    case listing.date_precision
    when "time"
      start_time = listing.starts_at.in_time_zone(listing.timezone)
      label = start_time.strftime("%-d %b %Y · %-I:%M %p")
      if listing.ends_at
        end_time = listing.ends_at.in_time_zone(listing.timezone)
        label += " – #{end_time.strftime(start_time.to_date == end_time.to_date ? '%-I:%M %p' : '%-d %b %Y · %-I:%M %p')}"
      end
      label + " · #{listing.timezone}"
    when "local_time"
      label = listing.starts_on.strftime("%-d %b %Y")
      label += " – #{listing.ends_on.strftime('%-d %b %Y')}" if listing.ends_on && listing.ends_on != listing.starts_on
      label += " · #{listing.local_start_time}"
      label += " – #{listing.local_end_time}" if listing.local_end_time
      label + " · #{listing.timezone || 'Timezone not published'}"
    when "date"
      range = listing.starts_on.strftime("%-d %b %Y")
      range += " – #{listing.ends_on.strftime('%-d %b %Y')}" if listing.ends_on && listing.ends_on != listing.starts_on
      range + " · Time not published"
    when "month"
      Date.new(listing.date_year, listing.date_month, 1).strftime("%B %Y") + " · Exact date not published"
    when "year"
      "#{listing.date_year} · Exact date not published"
    else
      "Date not published"
    end
  end

  def discovery_location(listing)
    return "Online" if listing.format == "online"
    country = listing.country_code == "IN" ? "India" : listing.country_code
    [ listing.city, country ].compact.join(", ").presence || "Location not published"
  end

  def discovery_state(listing)
    return "Dates need review" if listing.review_state == "hold"
    return "Canceled by source" if listing.status_canceled?
    return "Date unconfirmed" if listing.period == "uncertain"
    return "Past event" if listing.period == "past"
    listing.status_scheduled? ? "Upcoming / ongoing" : "Upcoming date · Status unconfirmed"
  end
end
