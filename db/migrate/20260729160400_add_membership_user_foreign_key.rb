class AddMembershipUserForeignKey < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :memberships, :users, validate: false
  end
end
