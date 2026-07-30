class Current < ActiveSupport::CurrentAttributes
  attribute :session, :organizer, :event
  delegate :admin_user, :user, to: :session, allow_nil: true

  def self.with_tenant(organizer:, event:, &block)
    set(organizer:, event:, &block)
  end
end
