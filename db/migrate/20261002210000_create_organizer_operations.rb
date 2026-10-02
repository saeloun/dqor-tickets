class CreateOrganizerOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations_business_contacts do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email
      t.boolean :outreach_approved, null: false, default: false
      t.timestamps
    end
    create_table :operations_sponsor_deals do |t|
      t.references :event, null: false, foreign_key: true
      t.references :business_contact, null: false, foreign_key: { to_table: :operations_business_contacts }
      t.string :title, null: false
      t.string :stage, null: false, default: "pledged"
      t.bigint :amount_paise, null: false
      t.string :contribution, null: false, default: "cash"
      t.timestamps
    end
    create_table :operations_vendor_engagements do |t|
      t.references :event, null: false, foreign_key: true
      t.references :business_contact, null: false, foreign_key: { to_table: :operations_business_contacts }
      t.string :title, null: false
      t.bigint :amount_paise, null: false
      t.timestamps
    end
    create_table :operations_fulfillment_tasks do |t|
      t.references :event, null: false, foreign_key: true
      t.references :sponsor_deal, null: false, foreign_key: { to_table: :operations_sponsor_deals }
      t.string :title, null: false
      t.date :due_on
      t.boolean :completed, null: false, default: false
      t.timestamps
    end
    create_table :operations_manual_entries do |t|
      t.references :event, null: false, foreign_key: true
      t.references :sponsor_deal, foreign_key: { to_table: :operations_sponsor_deals }
      t.references :vendor_engagement, foreign_key: { to_table: :operations_vendor_engagements }
      t.string :kind, null: false
      t.bigint :amount_paise, null: false
      t.date :occurred_on, null: false
      t.string :reference, null: false
      t.timestamps
    end
    create_table :operations_audit_logs do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.string :record_kind, null: false
      t.bigint :record_id, null: false
      t.timestamps
    end
    %i[sponsor_deals vendor_engagements manual_entries].each do |table|
      add_check_constraint "operations_#{table}", "amount_paise > 0", name: "#{table}_positive_amount"
    end
    add_check_constraint :operations_sponsor_deals, "stage IN ('pledged', 'committed') AND contribution IN ('cash', 'in_kind')", name: "sponsor_deal_categories"
    add_check_constraint :operations_manual_entries,
      "(sponsor_deal_id IS NOT NULL AND vendor_engagement_id IS NULL AND kind IN ('receipt', 'refund')) OR (sponsor_deal_id IS NULL AND vendor_engagement_id IS NOT NULL AND kind IN ('expense', 'expense_refund'))",
      name: "manual_entry_target"
  end
end
