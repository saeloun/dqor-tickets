module Platform
  module Commerce
    class Policy
      class Disabled < StandardError; end
      class Forbidden < StandardError; end

      ROLES = {
        read_inventory: %w[owner admin editor viewer],
        manage_inventory: %w[owner admin editor],
        read_attendees: %w[owner admin],
        export_attendees: %w[owner admin]
      }.freeze

      def initialize(user:, organization_id:, event_id:)
        @user_id = user.id if user.is_a?(User) && user.persisted?
        @organization_id = organization_id
        @event_id = event_id
      end

      # Resolve every time; never retain a stale membership or a lazy relation.
      # Holding the membership lock serializes mutations with revocation/demotion.
      def with_access(action)
        unless Rails.configuration.x.organizer_platform_enabled && Rails.configuration.x.staged_commerce_enabled
          raise Disabled, "Staged commerce is disabled"
        end
        raise Forbidden, "Organization membership required" unless @user_id

        Membership.transaction do
          membership = Membership.lock.find_by!(user_id: @user_id, organization_id: @organization_id)
          raise Forbidden, "Role does not permit this operation" unless ROLES.fetch(action).include?(membership.role)

          event = Event.lock.find_by!(id: @event_id, organization_id: membership.organization_id)
          yield event
        end
      end
    end
  end
end
