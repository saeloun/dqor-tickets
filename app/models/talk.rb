class Talk < ApplicationRecord
  EVENT_ZONE = "Asia/Kolkata".freeze

  has_many :talk_bookmarks, dependent: :destroy
  has_many :talk_feedbacks, dependent: :destroy
  has_many :talk_questions, dependent: :destroy
  belongs_to :speaker, optional: true

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

  def speaker_display
    speaker&.name.presence || speaker_name
  end

  def over?
    ended = ends_at || starts_at
    ended.present? && ended.past?
  end

  def average_rating
    talk_feedbacks.average(:rating)&.round(1)
  end

  def ratings_count
    talk_feedbacks.count
  end

  def feedback_from(user)
    return nil unless user

    talk_feedbacks.find_by(user_id: user.id)
  end
end
