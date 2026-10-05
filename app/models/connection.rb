class Connection < ApplicationRecord
  belongs_to :user
  belongs_to :connected_user, class_name: "User"

  validates :connected_user_id, uniqueness: { scope: :user_id }
  validate :not_self
  validate do
    errors.add(:base, "Networking unavailable") unless user&.legacy_network_eligible? && connected_user&.legacy_network_eligible?
  end

  private
    def not_self
      errors.add(:connected_user, "can't be yourself") if user_id == connected_user_id
    end
end
