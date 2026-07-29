class Membership < ApplicationRecord
  belongs_to :organizer
  belongs_to :user, optional: true

  enum :role, {
    owner: "owner",
    admin: "admin",
    editor: "editor",
    finance: "finance",
    checkin_operator: "checkin_operator",
    viewer: "viewer"
  }, validate: true

  validates :user_id, presence: true, uniqueness: { scope: :organizer_id }
end
