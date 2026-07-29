class Report < ApplicationRecord
  belongs_to :reporter, class_name: "User"
  belongs_to :reportable, polymorphic: true

  enum :status, { open: "open", reviewing: "reviewing", actioned: "actioned", dismissed: "dismissed" }, validate: true

  validates :reason, presence: true
end
