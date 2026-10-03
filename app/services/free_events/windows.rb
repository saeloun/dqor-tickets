module FreeEvents
  module Windows
    class Invalid < StandardError; end

    def self.enabled?
      Access.enabled? && Rails.configuration.x.free_registration_windows_enabled
    end

    def self.read(user:, organization_id:, event_id:, ticket_type_id:)
      raise ActiveRecord::RecordNotFound unless enabled?
      Access.with_manager(user: user, organization_id: organization_id, event_id: event_id) do |event|
        type = TicketType.where(event_id: event.id, price_paise: 0).find(ticket_type_id)
        window = RegistrationWindow.find_by(ticket_type: type) || RegistrationWindow.new(event: event, ticket_type: type, draft_timezone: event.timezone)
        yield event, type, window
      end
    end

    def self.change(action:, revision:, opens_local: nil, closes_local: nil, **access)
      read(**access) do |event, _type, window|
        raise Invalid, "Another organizer changed this draft. Reload and review it before saving or publishing." unless revision.to_s == window.lock_version.to_s
        window.lock_version = 1 if window.new_record?
        case action
        when "save"
          window.draft_opens_at = parse_local(opens_local, event.timezone)
          window.draft_closes_at = parse_local(closes_local, event.timezone)
          window.draft_timezone = event.timezone
          validate_dates!(event, window.draft_opens_at, window.draft_closes_at)
        when "publish"
          raise Invalid, "Save and preview a draft before publishing." if window.new_record?
          raise Invalid, "The event timezone changed. Save and review the draft again." unless window.draft_timezone == event.timezone
          validate_dates!(event, window.draft_opens_at, window.draft_closes_at)
          window.opens_at = window.draft_opens_at
          window.closes_at = window.draft_closes_at
          window.timezone = window.draft_timezone
          window.published_at = Time.current
        else
          raise ActiveRecord::RecordNotFound
        end
        window.save!
        window
      end
    end

    def self.validate_dates!(event, opens_at, closes_at)
      raise Invalid, "Add event dates before setting registration windows." unless event.ends_at
      finish = closes_at || event.ends_at
      raise Invalid, "Registration must close after it opens." if opens_at && finish <= opens_at
      raise Invalid, "Registration cannot close after the event ends." if finish > event.ends_at
    end

    def self.parse_local(value, timezone)
      return nil if value.blank?
      raise Invalid, "Use a local date and time in YYYY-MM-DD HH:MM format." unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)
      parts = value.scan(/\d+/).map(&:to_i)
      raise Invalid, "Enter a valid local date and time." unless parts[0].positive? && Date.valid_date?(*parts.first(3)) && parts[3].between?(0, 23) && parts[4].between?(0, 59)
      wall = Time.utc(*parts)
      periods = TZInfo::Timezone.get(timezone).periods_for_local(wall)
      raise Invalid, "This local time does not exist because the clocks change. Choose another time." if periods.empty?
      raise Invalid, "This local time occurs twice because the clocks change. Choose an unambiguous time." if periods.length > 1
      wall - periods.first.utc_total_offset
    end
  end
end
