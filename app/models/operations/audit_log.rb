class Operations::AuditLog < Operations::Record
  belongs_to :user
  validates :action, :record_kind, :record_id, presence: true

  def readonly?
    persisted?
  end
end
