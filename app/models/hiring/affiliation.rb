# Self-reported employment only. Never consulted by authorization policies.
class Hiring::Affiliation < ApplicationRecord
  belongs_to :company
  belongs_to :user
  validates :user_id, uniqueness: { scope: :company_id }
end
