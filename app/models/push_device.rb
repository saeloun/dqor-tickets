class PushDevice < ApplicationRecord
  belongs_to :user

  enum :platform, { ios: "ios", android: "android", web: "web" }, validate: true

  validates :token, presence: true, uniqueness: { scope: :platform }
end
