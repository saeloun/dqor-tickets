class AddSocialProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :website, :string
    add_column :users, :x_username, :string
    add_column :users, :bluesky, :string
    add_column :users, :github, :string
    add_column :users, :mastodon, :string
    add_column :users, :linkedin, :string
  end
end
