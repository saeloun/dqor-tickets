class PersonalScheduleEntry < ApplicationRecord
  belongs_to :registration
  belongs_to :program_session

  validates :program_session_id, uniqueness: { scope: :registration_id }
  validate :session_matches_registration_event

  private
    def session_matches_registration_event
      return if registration.nil? || program_session.nil?

      errors.add(:program_session, "must belong to the same event") if program_session.event_id != registration.event_id
    end
end
