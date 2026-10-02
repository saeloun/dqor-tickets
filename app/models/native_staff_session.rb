require "digest"

class NativeStaffSession < ApplicationRecord
  EVENT = "dqor-2026"
  CAPABILITIES = %w[tickets:read checkins:write].freeze
  belongs_to :admin_user

  def self.enabled?
    ENV["NATIVE_STAFF_API_ENABLED"] == "true"
  end

  def self.configured_dates
    dates = ENV.fetch("NATIVE_STAFF_EVENT_DATES", "").split(",").map { |value| Date.iso8601(value.strip) }
    return [] unless dates.any? && (dates - Ticket::EVENT_DATES).empty?

    dates.uniq.map(&:iso8601)
  rescue Date::Error
    []
  end

  def self.issue!(admin_user)
    raw_token = SecureRandom.urlsafe_base64(32)
    session = create!(admin_user:, token_digest: Digest::SHA256.hexdigest(raw_token),
      password_fingerprint: Digest::SHA256.hexdigest(admin_user.password_digest), role: admin_user.role,
      event: EVENT, event_dates: configured_dates, capabilities: CAPABILITIES, expires_at: 8.hours.from_now)
    [ session, raw_token ]
  end

  def valid_for_operator?
    expires_at.future? && event == EVENT && role == admin_user.role &&
      (admin_user.admin? || admin_user.desk?) &&
      ActiveSupport::SecurityUtils.secure_compare(password_fingerprint, Digest::SHA256.hexdigest(admin_user.password_digest))
  end

  def allows?(capability, date)
    capabilities.include?(capability) && event_dates.include?(date) && self.class.configured_dates.include?(date)
  end
end
