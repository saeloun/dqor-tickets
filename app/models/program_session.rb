class ProgramSession < ApplicationRecord
  belongs_to :event
  belongs_to :track, optional: true
  belongs_to :room, optional: true

  has_many :program_session_speakers, dependent: :destroy
  has_many :speakers, through: :program_session_speakers
  has_many :video_assets, dependent: :destroy

  enum :kind, {
    talk: "talk",
    keynote: "keynote",
    workshop: "workshop",
    panel: "panel",
    lightning: "lightning",
    break: "break",
    social: "social"
  }, validate: true

  enum :state, { draft: "draft", confirmed: "confirmed", cancelled: "cancelled" }, validate: true

  validates :title, presence: true
  validate :times_are_ordered

  scope :ordered, -> { order(:starts_at, :position, :id) }
  scope :scheduled, -> { where.not(starts_at: nil) }

  private
    def times_are_ordered
      errors.add(:ends_at, "must be after start") if starts_at && ends_at && ends_at < starts_at
    end
end
