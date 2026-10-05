class Hiring::Job < ApplicationRecord
  belongs_to :company
  belongs_to :event, optional: true
  belongs_to :recruiter, class_name: "User"
  validates :title, :description, presence: true
  validates :title, length: { maximum: 255 }
  validates :description, length: { maximum: 10000 }
  validate :scoped_employer

  scope :visible, -> { joins(:company).where(open: true, hiring_companies: { status: "approved" }).where(event_id: nil).or(joins(:company).where(open: true, hiring_companies: { status: "approved" }, event_id: Event.published.select(:id))) }

  private
    def scoped_employer
      errors.add(:company, "must have an approved claim") unless company&.status == "approved"
      errors.add(:recruiter, "must own the approved claim") unless company&.claimant_id == recruiter_id
      errors.add(:event, "must belong to the company organization") if event && event.organization_id != company&.organization_id
    end
end
