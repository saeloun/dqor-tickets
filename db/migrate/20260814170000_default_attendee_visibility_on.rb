class DefaultAttendeeVisibilityOn < ActiveRecord::Migration[8.1]
  # Metadata-only default flips (no table rewrite, no lock). Existing rows are
  # left untouched on purpose — only new attendees pick up the opt-out default.
  def up
    change_column_default :users, :discoverable, from: false, to: true
    change_column_default :users, :public_attendee, from: false, to: true
  end

  def down
    change_column_default :users, :discoverable, from: true, to: false
    change_column_default :users, :public_attendee, from: true, to: false
  end
end
