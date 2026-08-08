class AddLogoPathToSponsors < ActiveRecord::Migration[8.1]
  def change
    add_column :sponsors, :logo_path, :string
  end
end
