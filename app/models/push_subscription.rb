class PushSubscription < ApplicationRecord
  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true

  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
end
