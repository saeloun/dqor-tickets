class AddAnnouncementsSeenAtToUsers < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '8s'"
    add_column :users, :announcements_seen_at, :datetime
  end

  def down
    remove_column :users, :announcements_seen_at
  end
end
