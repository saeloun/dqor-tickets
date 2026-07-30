class Account < ApplicationRecord
  has_many :organizers, dependent: :restrict_with_exception

  normalizes :billing_email, with: ->(email) { email.strip.downcase }

  validates :name, :country, :status, presence: true
  validates :billing_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :country, format: { with: /\A[A-Z]{2}\z/ }
end
