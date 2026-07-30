class Connection < ApplicationRecord
  belongs_to :user
  belongs_to :connected_user, class_name: "User"

  validates :connected_user_id, uniqueness: { scope: :user_id }
  validate :not_self

  private
    def not_self
      errors.add(:connected_user, "can't be yourself") if user_id == connected_user_id
    end
end
