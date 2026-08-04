class AddStatusToSpeakers < ActiveRecord::Migration[8.1]
  def change
    # 0 = pending (non-public) so no speaker is ever public by default.
    add_column :speakers, :status, :integer, default: 0, null: false
    add_index :speakers, :status
  end
end
