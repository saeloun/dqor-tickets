class Event < ApplicationRecord
  belongs_to :organization

  enum :status, { draft: "draft", published: "published" }, validate: true
  normalizes :slug, with: ->(value) { value.to_s.strip.downcase }
  validates :title, :slug, :timezone, presence: true, length: { maximum: 255 }
  validates :slug, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :starts_at, :ends_at, presence: true, if: :published?
  validate :valid_timezone
  normalizes :source_url, with: ->(value) { canonical_source_url(value) }
  normalizes :external_registration_url, :cfp_url, with: ->(value) { value.presence }
  validates :source_url, uniqueness: { scope: :organization_id }, allow_nil: true
  validates :description, length: { maximum: 10_000 }
  validates :venue_name, length: { maximum: 255 }
  validates :venue_address, length: { maximum: 2_000 }
  validates :topics, length: { maximum: 1_000 }
  validates :import_notes, length: { maximum: 20_000 }
  validate :safe_external_urls
  validate :ordered_dates

  def self.canonical_source_url(value)
    return if value.blank?

    uri = URI.parse(value)
    if %w[http https].include?(uri.scheme) && %w[lu.ma luma.com].include?(uri.host&.downcase) && uri.path.match?(%r{\A/[a-zA-Z0-9]+/?\z}) && uri.userinfo.nil? && [ 80, 443 ].include?(uri.port)
      uri.scheme = "https"
      uri.host = "luma.com"
      uri.port = nil
      uri.path = uri.path.delete_suffix("/")
      uri.fragment = nil
      pairs = URI.decode_www_form(uri.query.to_s).reject { |key, _| key.start_with?("utm_") }
      uri.query = pairs.empty? ? nil : URI.encode_www_form(pairs)
    end
    uri.to_s
  rescue URI::InvalidURIError, ArgumentError
    value
  end

  private
    def safe_external_urls
      %i[source_url external_registration_url cfp_url].each do |attribute|
        value = public_send(attribute)
        next if value.nil?

        uri = URI.parse(value)
        valid = value.length <= 2_048 && !value.match?(/[\s\p{Cc}]/) && %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?
        errors.add(attribute, "must be a complete HTTP or HTTPS URL without credentials or whitespace") unless valid
      rescue URI::InvalidURIError
        errors.add(attribute, "must be a complete HTTP or HTTPS URL without credentials or whitespace")
      end
    end

    def valid_timezone
      TZInfo::Timezone.get(timezone.to_s)
    rescue TZInfo::InvalidTimezoneIdentifier
      errors.add(:timezone, "must be an IANA timezone, such as Asia/Kolkata")
    end

    def ordered_dates
      errors.add(:ends_at, "must be after start") if starts_at && ends_at && ends_at <= starts_at
    end
end
