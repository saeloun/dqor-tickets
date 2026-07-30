class Question < ApplicationRecord
  KINDS = %w[short_text long_text boolean single_choice multi_choice number country phone date file].freeze
  ANSWER_SCOPES = %w[order attendee].freeze
  ASK_AT = %w[checkout checkin both].freeze

  belongs_to :event
  belongs_to :dependency_question, class_name: "Question", optional: true
  has_many :answers, dependent: :destroy

  validates :label, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :answer_scope, inclusion: { in: ANSWER_SCOPES }
  validates :ask_at, inclusion: { in: ASK_AT }

  scope :enabled, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :for_checkout, -> { where(ask_at: %w[checkout both]) }
  scope :for_checkin, -> { where(ask_at: %w[checkin both]) }

  def choice?
    kind.in?(%w[single_choice multi_choice])
  end
end
