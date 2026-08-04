class AdminUser < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  # admin: full Avo access. desk: registration-desk staff — check-in scanner only.
  enum :role, { admin: 0, desk: 1 }, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 8 }, allow_nil: true

  def display_name
    name.presence || email.split("@").first
  end
end
