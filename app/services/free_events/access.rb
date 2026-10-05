module FreeEvents
  module Access
    def self.enabled?
      Rails.configuration.x.organizer_platform_enabled && Rails.configuration.x.free_event_pilot_enabled
    end

    def self.require_enabled!
      raise ActiveRecord::RecordNotFound unless enabled?
    end

    def self.with_manager(user:, organization_id:, event_id:)
      require_enabled!
      raise ActiveRecord::RecordNotFound unless user.is_a?(User) && user.persisted?
      Membership.transaction do
        membership = Membership.lock.find_by!(user: user, organization_id: organization_id, role: %w[owner admin])
        event = Event.lock.find_by!(id: event_id, organization_id: membership.organization_id)
        yield event
      end
    end
  end
end
