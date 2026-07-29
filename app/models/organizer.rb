class Organizer < ApplicationRecord
  belongs_to :account

  has_one_attached :logo

  has_many :tax_profiles, dependent: :restrict_with_exception
  has_many :memberships, dependent: :restrict_with_exception
  has_many :events, dependent: :restrict_with_exception
  has_many :invoice_sequences, dependent: :restrict_with_exception
  has_many :orders, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception
  has_many :payouts, dependent: :restrict_with_exception

  enum :payout_mode, { direct: "direct", route: "route" }, validate: true

  normalizes :slug, with: ->(slug) { slug.strip.downcase }
  normalizes :support_email, with: ->(email) { email.strip.downcase }

  validates :name, :slug, :default_currency, :default_timezone, :status, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :support_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :default_currency, format: { with: /\A[A-Z]{3}\z/ }
end
