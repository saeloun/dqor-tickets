module FreeEvents
  module Privacy
    def self.enroll!(user)
      user.with_lock do
        # Shared DQOR attendees keep their existing visibility choices. This is
        # a per-user transition, never a roster grant or bulk visibility change.
        unless user.free_pilot_identity? || user.attending?
          user.update!(free_pilot_identity: true, discoverable: false, public_attendee: false)
        end
      end
    end
  end
end
