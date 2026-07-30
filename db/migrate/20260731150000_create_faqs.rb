class CreateFaqs < ActiveRecord::Migration[8.1]
  def change
    create_table :faqs do |t|
      t.string :question, null: false
      t.text :answer
      t.boolean :published, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :faqs, [ :published, :position ]
  end
end
