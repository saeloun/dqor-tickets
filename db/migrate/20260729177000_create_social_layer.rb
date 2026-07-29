class CreateSocialLayer < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :followable, polymorphic: true, null: false
      t.timestamps
      t.index [ :user_id, :followable_type, :followable_id ], unique: true, name: "index_follows_uniqueness"
    end

    create_table :posts do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :pinned, null: false, default: false
      t.timestamps
    end

    create_table :comments do |t|
      t.references :post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    create_table :reactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reactable, polymorphic: true, null: false
      t.string :kind, null: false, default: "like"
      t.timestamps
      t.index [ :user_id, :reactable_type, :reactable_id, :kind ], unique: true, name: "index_reactions_uniqueness"
    end

    create_table :reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reportable, polymorphic: true, null: false
      t.string :reason, null: false
      t.string :status, null: false, default: "open"
      t.text :notes
      t.timestamps
    end
  end
end
