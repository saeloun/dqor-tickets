class Reaction < ApplicationRecord
  belongs_to :user
  belongs_to :reactable, polymorphic: true

  validates :kind, presence: true
  validates :user_id, uniqueness: { scope: [ :reactable_type, :reactable_id, :kind ] }
end
