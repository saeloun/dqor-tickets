class AddEmailedAtToAnnouncements < ActiveRecord::Migration[8.1]
  def change
    add_column :announcements, :emailed_at, :datetime
  end
end
