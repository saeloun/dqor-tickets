class Discovery::Listing < ApplicationRecord
  self.table_name = "discovery_listings"
  belongs_to :primary_source, class_name: "Discovery::Source"
  has_many :references, class_name: "Discovery::Reference", dependent: :restrict_with_exception

  enum :status, { scheduled: "scheduled", canceled: "canceled", unknown: "unknown" }, prefix: true, validate: true
  validates :title, :canonical_url, :date_precision, :format, presence: true
  validates :title, length: { maximum: 200 }
  validates :identity_key, presence: true, uniqueness: true
  validates :city, length: { maximum: 120 }
  validates :country_code, format: { with: /\A[A-Z]{2}\z/ }, allow_nil: true
  validates :date_precision, inclusion: { in: %w[time local_time date month year unknown] }
  validates :format, inclusion: { in: %w[in_person online hybrid unknown] }

  def self.in_period(period, now: Time.current)
    case period
    when "upcoming"
      where.not(status: "canceled").where(review_state: "clear").where("(date_precision = 'time' AND COALESCE(ends_at, starts_at) >= :now) OR (date_precision IN ('date', 'local_time') AND COALESCE(ends_on, starts_on) >= (:now::timestamptz AT TIME ZONE COALESCE(timezone, 'UTC'))::date)", now: now)
    when "weekend"
      today = now.in_time_zone("Asia/Kolkata").to_date
      saturday = today.sunday? ? today - 1 : today + (6 - today.wday) % 7
      in_period("upcoming", now: now).where("starts_on <= :sunday AND COALESCE(ends_on, starts_on) >= :saturday AND (cardinality(occurrence_dates) = 0 OR EXISTS (SELECT 1 FROM unnest(occurrence_dates) AS event_day(published_on) WHERE published_on BETWEEN :saturday AND :sunday))", saturday: saturday, sunday: saturday + 1)
    when "past"
      where(review_state: "clear").where("(date_precision = 'time' AND COALESCE(ends_at, starts_at) < :now) OR (date_precision IN ('date', 'local_time') AND COALESCE(ends_on, starts_on) < (:now::timestamptz AT TIME ZONE COALESCE(timezone, 'UTC'))::date)", now: now)
    when "uncertain"
      where("date_precision IN ('month', 'year', 'unknown') OR review_state = 'hold'")
    else
      all
    end
  end

  def period(now: Time.current)
    return "uncertain" if review_state == "hold"
    return "uncertain" unless %w[time date local_time].include?(date_precision)
    if date_precision == "time"
      (ends_at || starts_at) >= now ? "upcoming" : "past"
    else
      (ends_on || starts_on) >= now.in_time_zone(timezone || "UTC").to_date ? "upcoming" : "past"
    end
  end
end
