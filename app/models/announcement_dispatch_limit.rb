class AnnouncementDispatchLimit < ApplicationRecord
  PER_MINUTE = 25

  def self.control
    create_or_find_by!(id: 1) { |record| record.window_started_at = Time.current }
  end

  def self.claim
    control
    transaction do
      limit = lock.find(1)
      if limit.window_started_at <= 1.minute.ago
        limit.update!(window_started_at: Time.current, used: 0)
      end
      return if limit.used >= PER_MINUTE
      delivery = AnnouncementDelivery.where(state: "pending").order(:id).lock.first
      return unless delivery
      limit.update!(used: limit.used + 1)
      delivery.update!(state: "preparing", attempted_at: Time.current, attempts: delivery.attempts + 1)
      delivery
    end
  end
end
