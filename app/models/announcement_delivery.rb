class AnnouncementDelivery < ApplicationRecord
  belongs_to :announcement_campaign
  STATES = %w[pending preparing submitting submitted suppressed failed unknown].freeze
  validates :state, inclusion: { in: STATES }

  # A process lost during preparation has not contacted the transport. A process
  # lost after the submission marker may have sent mail: never retry that state.
  def self.recover_stale!
    where(state: "preparing").where("attempted_at < ?", 15.minutes.ago).update_all(state: "failed", error_class: "PreparationInterrupted")
    where(state: "submitting").where("attempted_at < ?", 15.minutes.ago).update_all(state: "unknown", error_class: "SubmissionInterrupted")
  end
end
