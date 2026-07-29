class EmailSequenceStep < ApplicationRecord
  TRIGGER_TYPES = %w[on_registration on_ticket_purchase relative_to_event_start relative_to_event_end].freeze
  MERGE_FIELDS = %w[name event_title schedule_link ticket_link].freeze

  belongs_to :event
  has_many :email_sequence_sends, dependent: :destroy

  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }
  validates :subject, :body, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  def relative?
    trigger_type.start_with?("relative_")
  end

  def render_subject(merge_values)
    interpolate(subject, merge_values)
  end

  def render_body(merge_values)
    interpolate(body, merge_values)
  end

  private
    def interpolate(text, values)
      text.gsub(/\{(\w+)\}/) { values[$1.to_sym] || values[$1] || "" }
    end
end
