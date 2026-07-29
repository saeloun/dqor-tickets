class User < ApplicationRecord
  include Avatarable

  has_one_attached :avatar

  has_many :identities, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :registrations, dependent: :destroy
  has_many :organized_organizers, through: :memberships, source: :organizer
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :reactions, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.strip }
  normalizes :github_login, with: ->(login) { login.to_s.strip.presence }

  validates :email, :name, presence: true
  validates :email, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :timezone, presence: true

  def first_name
    name.to_s.split(" ").first
  end

  def initials
    name.to_s.split(" ").map { |part| part.chars.first&.upcase }.compact.first(2).join
  end

  def avatar_url
    avatar.attached? ? Rails.application.routes.url_helpers.rails_blob_path(avatar, only_path: true) : nil
  end

  def github_avatar_url
    github_login.present? ? "https://github.com/#{github_login}.png?size=256" : nil
  end

  def gravatar_url
    return nil if email.blank?

    hash = Digest::SHA256.hexdigest(email.downcase)
    "https://www.gravatar.com/avatar/#{hash}?d=identicon&r=pg&s=256"
  end
end
