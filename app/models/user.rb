class User < ApplicationRecord
  SOCIAL_PROFILE_FIELDS = %i[website x_username bluesky github mastodon linkedin].freeze

  has_secure_password validations: false
  has_one_attached :avatar

  has_many :connections, dependent: :destroy
  has_many :connected_users, through: :connections, source: :connected_user
  has_many :inbound_connections, class_name: "Connection", foreign_key: :connected_user_id, dependent: :destroy
  has_many :connectors, through: :inbound_connections, source: :user
  has_many :talk_bookmarks, dependent: :destroy
  has_many :bookmarked_talks, through: :talk_bookmarks, source: :talk

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :x_username, :bluesky, :github, :mastodon, :linkedin,
    with: ->(value) { value.to_s.strip.sub(/\A@/, "") }
  normalizes :website, with: ->(value) {
    website = value.to_s.strip
    website.blank? || website.match?(/\A[a-z][a-z0-9+.-]*:\/\//i) ? website : "https://#{website}"
  }

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates(*SOCIAL_PROFILE_FIELDS, length: { maximum: 255 }, allow_blank: true)
  validate :website_is_http_url

  def paid_orders
    Order.paid.where("lower(orders.email) = ?", email)
  end

  def tickets
    Ticket.joins(:order).merge(paid_orders)
  end

  def gravatar_url(size: 200)
    hash = Digest::MD5.hexdigest(email.to_s.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end

  def connected_to?(other)
    connections.exists?(connected_user_id: other.id)
  end

  def bookmarked?(talk)
    talk_bookmarks.exists?(talk_id: talk.id)
  end

  def display_name
    name.presence || email.split("@").first
  end

  private
    def website_is_http_url
      return if website.blank?

      uri = URI.parse(website)
      errors.add(:website, "must be a valid http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:website, "must be a valid http(s) URL")
    end
end
