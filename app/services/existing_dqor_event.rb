# Staged lookup only. No current checkout, tickets, or content use this adapter.
# Callers must never infer that legacy commerce records are tenant scoped.
class ExistingDqorEvent
  def self.resolve
    return unless Rails.configuration.x.organizer_platform_enabled

    id = ENV["DQOR_PLATFORM_EVENT_ID"]
    return unless id.to_s.match?(/\A[1-9][0-9]*\z/)

    Event.published.find_by(id: id)
  end
end
