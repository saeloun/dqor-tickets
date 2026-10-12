module CommunityGroups
  module Access
    def self.enabled?
      FreeEvents::Access.enabled? && Rails.configuration.x.meetup_groups_enabled
    end

    def self.with_manager(user:, organization_id:)
      raise ActiveRecord::RecordNotFound unless enabled? && user.is_a?(User) && user.persisted?
      Membership.transaction do
        membership = Membership.lock.find_by!(user: user, organization_id: organization_id, role: %w[owner admin])
        yield membership.organization
      end
    end

    def self.attach_event(user:, organization_id:, group_id:, event_id:)
      with_manager(user: user, organization_id: organization_id) do |organization|
        group = organization.community_groups.lock.find(group_id)
        event = organization.events.lock.find(event_id)
        if event.community_group_id && event.community_group_id != group.id
          event.errors.add(:community_group, "already belongs to another community")
          raise ActiveRecord::RecordInvalid, event
        end
        event.update!(community_group: group) unless event.community_group_id == group.id
        event
      end
    end
  end
end
