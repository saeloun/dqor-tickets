class Session < ApplicationRecord
  belongs_to :admin_user, optional: true
  belongs_to :user, optional: true

  validate :account_present

  def account
    user || admin_user
  end

  private
    def account_present
      errors.add(:base, "must belong to a user or admin user") unless account.present?
    end
end
