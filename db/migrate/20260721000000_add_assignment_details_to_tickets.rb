class AddAssignmentDetailsToTickets < ActiveRecord::Migration[8.0]
  def up
    add_column :tickets, :assigned_at, :datetime
    add_column :tickets, :childcare_needed, :boolean, null: false, default: false
    add_column :tickets, :claim_token, :string

    select_values("SELECT id FROM tickets WHERE claim_token IS NULL").each do |id|
      execute "UPDATE tickets SET claim_token = #{connection.quote(SecureRandom.base58(24))} WHERE id = #{connection.quote(id)}"
    end

    add_index :tickets, :claim_token, unique: true
  end

  def down
    remove_index :tickets, :claim_token
    remove_columns :tickets, :assigned_at, :childcare_needed, :claim_token
  end
end
