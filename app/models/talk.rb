class Talk < ApplicationRecord
  EVENT_ZONE = "Asia/Kolkata".freeze

  scope :published, -> { where(published: true) }
  scope :scheduled, -> { order(Arel.sql("starts_at IS NULL"), :starts_at, :position, :title) }

  validates :title, presence: true

  def local_start
    starts_at&.in_time_zone(EVENT_ZONE)
  end

  def day
    local_start&.to_date
  end

  def time_range
    return "Time to be announced" unless local_start

    text = local_start.strftime("%-l:%M %p")
    text += " – #{ends_at.in_time_zone(EVENT_ZONE).strftime("%-l:%M %p")}" if ends_at
    text
  end
end
