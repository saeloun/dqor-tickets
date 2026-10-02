class Hiring::Company < ApplicationRecord
  belongs_to :organization
  belongs_to :claimant, class_name: "User"
  belongs_to :reviewer, class_name: "User", optional: true
  validates :name, :website, :evidence, presence: true
  validates :name, :website, length: { maximum: 255 }
  validates :evidence, length: { maximum: 5000 }
  validates :website, format: { with: %r{\Ahttps://[^\s/]+(?:/[^\s]*)?\z} }
  validates :status, inclusion: { in: %w[pending approved rejected] }
end
