module NativeAttendee
  module RateLimit
    class Unavailable < StandardError; end
    class Exceeded < StandardError; end

    def self.check!(name, identity, maximum:, within:)
      store = Rails.cache
      raise Unavailable if Rails.env.production? && !store.is_a?(SolidCache::Store)

      digest = Digest::SHA256.hexdigest(identity.to_s)
      key = "native-attendee-rate:#{name}:#{digest}"
      lock_id = Digest::SHA256.digest(key).unpack1("q>")
      count = SolidCache::Record.transaction do
        SolidCache::Record.connection.execute("SET LOCAL lock_timeout = '1s'")
        SolidCache::Record.connection.execute("SELECT pg_advisory_xact_lock(#{lock_id})")
        store.increment(key, 1, expires_in: within)
      end
      raise Unavailable unless count.is_a?(Integer)
      raise Exceeded if count > maximum
    rescue Exceeded, Unavailable
      raise
    rescue StandardError
      raise Unavailable
    end
  end
end
