class EmailSequenceSend < ApplicationRecord
  belongs_to :email_sequence_step
  belongs_to :registration

  validates :registration_id, uniqueness: { scope: :email_sequence_step_id }
end
