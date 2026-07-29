class CheckinRecord < ApplicationRecord
  belongs_to :event
  belongs_to :ticket
  belongs_to :program_session, optional: true
  belongs_to :operator_user, class_name: "User", optional: true

  enum :direction, { entry: "entry", exit: "exit" }, validate: true

  before_validation :stamp_recorded_at, on: :create

  scope :successful, -> { where(successful: true) }
  scope :chronological, -> { order(:recorded_at, :id) }

  private
    def stamp_recorded_at
      self.recorded_at ||= Time.current
    end
end
