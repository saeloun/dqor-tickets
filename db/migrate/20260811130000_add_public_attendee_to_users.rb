class AddPublicAttendeeToUsers < ActiveRecord::Migration[8.1]
  # Explicit, opt-in consent to be shown publicly as attending (the "who's
  # coming" face-pile + an "attending" badge on the profile). Off by default —
  # narrower `discoverable` (the attendee directory) does NOT imply this.
  def up
    # Bound any lock wait so db:prepare can't hang boot (see the sponsor
    # migrations); still needed until the prod disk is removed.
    execute "SET LOCAL lock_timeout = '8s'"

    unless column_exists?(:users, :public_attendee)
      add_column :users, :public_attendee, :boolean, default: false, null: false
    end

    User.reset_column_information
    # The owner asked to opt in.
    User.where(email: "vipul@saeloun.com").update_all(public_attendee: true)
  end

  def down
    remove_column :users, :public_attendee if column_exists?(:users, :public_attendee)
  end
end
