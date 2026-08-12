class User < ApplicationRecord
  SOCIAL_PROFILE_FIELDS = %i[website x_username bluesky github mastodon linkedin].freeze

  has_secure_password validations: false
  has_one_attached :avatar

  before_create :assign_referral_code

  def self.generate_referral_code
    loop do
      code = SecureRandom.alphanumeric(7).upcase
      break code unless exists?(referral_code: code)
    end
  end

  has_many :connections, dependent: :destroy
  has_many :connected_users, through: :connections, source: :connected_user
  has_many :inbound_connections, class_name: "Connection", foreign_key: :connected_user_id, dependent: :destroy
  has_many :connectors, through: :inbound_connections, source: :user
  has_many :talk_bookmarks, dependent: :destroy
  has_many :bookmarked_talks, through: :talk_bookmarks, source: :talk
  has_many :talk_feedbacks, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id, dependent: :destroy

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

  # Opted-in, named users who actually hold a confirmed pass — the only people
  # shown on the public "who's coming" wall. Opt-in is off by default.
  scope :publicly_attending, -> {
    emails = Ticket.confirmed.where.not(attendee_email: [ nil, "" ]).distinct.pluck(Arel.sql("lower(attendee_email)"))
    where(public_attendee: true).where.not(name: [ nil, "" ]).where(email: emails)
  }

  def paid_orders
    Order.paid.where("lower(orders.email) = ?", email)
  end

  def tickets
    Ticket.joins(:order).merge(paid_orders)
  end

  # Holds a confirmed pass (bought one, or is named on one).
  def attending?
    paid_orders.exists? || Ticket.confirmed.where("lower(attendee_email) = ?", email).exists?
  end

  # Paid orders placed via this user's referral link.
  def referrals_count
    Order.paid.where("metadata ->> 'referred_by' = ?", referral_code).count
  end

  def assign_referral_code
    self.referral_code ||= self.class.generate_referral_code
  end

  def gravatar_url(size: 200)
    hash = Digest::MD5.hexdigest(email.to_s.strip.downcase)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=identicon"
  end

  def connected_to?(other)
    connections.exists?(connected_user_id: other.id)
  end

  def conversations
    Conversation.for_user(self)
  end

  # You can DM anyone you've connected with, or who has connected with you.
  def can_message?(other)
    return false if other.nil? || other == self

    connected_to?(other) || other.connected_to?(self)
  end

  def unread_messages_count
    conversations.includes(:messages).sum { |conversation| conversation.unread_count_for(self) }
  end

  def unread_announcements_count
    scope = Announcement.published
    scope = scope.where("coalesce(published_at, created_at) > ?", announcements_seen_at) if announcements_seen_at
    scope.count
  end

  def mark_announcements_seen!
    update_column(:announcements_seen_at, Time.current)
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
