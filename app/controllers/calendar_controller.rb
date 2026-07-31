class CalendarController < ApplicationController
  allow_unauthenticated_access

  def show
    send_data ics.gsub("\n", "\r\n"), filename: "deccan-queen-on-rails.ics", type: "text/calendar", disposition: "attachment"
  end

  private
    def ics
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Deccan Queen on Rails//EN
        CALSCALE:GREGORIAN
        BEGIN:VEVENT
        UID:dqor-2026@deccanqueenonrails.com
        DTSTAMP:20260101T000000Z
        DTSTART;VALUE=DATE:20261008
        DTEND;VALUE=DATE:20261012
        SUMMARY:Deccan Queen on Rails 2026
        LOCATION:Hyatt Regency, Pune
        DESCRIPTION:India's Ruby and Rails conference in Pune. https://deccanqueenonrails.com
        END:VEVENT
        END:VCALENDAR
      ICS
    end
end
