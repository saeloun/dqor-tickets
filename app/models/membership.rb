class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", editor: "editor", viewer: "viewer" }, validate: true
  validates :user_id, uniqueness: { scope: :organization_id }

  def manage_events?
    owner? || admin? || editor?
  end
end
