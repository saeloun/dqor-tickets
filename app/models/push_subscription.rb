class PushSubscription < ApplicationRecord
  belongs_to :user
  validate { errors.add(:user, "Networking unavailable") unless user&.legacy_network_eligible? }

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, :auth, presence: true
end
