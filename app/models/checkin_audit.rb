class CheckinAudit < ApplicationRecord
  belongs_to :ticket, optional: true
  belongs_to :admin_user, optional: true

  validates :event_date, presence: true
  validates :source, inclusion: { in: %w[scanner manual batch] }
  validates :outcome, inclusion: { in: %w[success duplicate canceled not_found unconfirmed wrong_date] }
end
