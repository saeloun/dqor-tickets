class Answer < ApplicationRecord
  belongs_to :question
  belongs_to :order, optional: true
  belongs_to :ticket, optional: true

  validate :exactly_one_subject

  private
    def exactly_one_subject
      errors.add(:base, "answer must belong to exactly one order or ticket") unless order_id.present? ^ ticket_id.present?
    end
end
