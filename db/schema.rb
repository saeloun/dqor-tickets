# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_19_090000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index "lower(email)", name: "index_admin_users_on_lower_email", unique: true
  end

  create_table "coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "discount_paise"
    t.integer "max_uses"
    t.integer "percent"
    t.integer "ticket_type_id"
    t.datetime "updated_at", null: false
    t.integer "uses_count", default: 0, null: false
    t.datetime "valid_from"
    t.datetime "valid_until"
    t.index "lower(code)", name: "index_coupons_on_lower_code", unique: true
    t.index ["ticket_type_id"], name: "index_coupons_on_ticket_type_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.json "buyer_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.date "issued_on", null: false
    t.string "kind", default: "invoice", null: false
    t.json "line_items", default: [], null: false
    t.string "number", null: false
    t.integer "order_id", null: false
    t.integer "refers_to_id"
    t.datetime "updated_at", null: false
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["order_id"], name: "index_invoices_one_invoice_per_order", unique: true, where: "kind = 'invoice'"
    t.index ["refers_to_id"], name: "index_invoices_on_refers_to_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "billing_state_code", limit: 2
    t.string "buyer_name", null: false
    t.string "buyer_phone"
    t.string "code", null: false
    t.integer "coupon_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at"
    t.string "gst_legal_name"
    t.string "gstin"
    t.json "metadata", default: {}, null: false
    t.string "razorpay_order_id"
    t.integer "status", default: 0, null: false
    t.integer "total_paise", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_orders_on_code", unique: true
    t.index ["coupon_id"], name: "index_orders_on_coupon_id"
    t.index ["razorpay_order_id"], name: "index_orders_on_razorpay_order_id", unique: true
  end

  create_table "payment_events", force: :cascade do |t|
    t.integer "amount_paise", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "order_id", null: false
    t.json "raw", default: {}, null: false
    t.string "razorpay_event_id", null: false
    t.string "razorpay_payment_id"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payment_events_on_order_id"
    t.index ["razorpay_event_id"], name: "index_payment_events_on_razorpay_event_id", unique: true
    t.index ["razorpay_payment_id"], name: "index_payment_events_on_razorpay_payment_id", unique: true, where: "razorpay_payment_id IS NOT NULL"
  end

  create_table "refunds", force: :cascade do |t|
    t.integer "amount_paise", null: false
    t.datetime "created_at", null: false
    t.string "credit_note_number"
    t.integer "order_id", null: false
    t.string "razorpay_refund_id"
    t.string "status", null: false
    t.json "ticket_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_refunds_on_order_id"
    t.index ["razorpay_refund_id"], name: "index_refunds_on_razorpay_refund_id", unique: true, where: "razorpay_refund_id IS NOT NULL"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["admin_user_id"], name: "index_sessions_on_admin_user_id"
  end

  create_table "ticket_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "hidden", default: false, null: false
    t.integer "max_per_order"
    t.integer "min_per_order", default: 1, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_paise", null: false
    t.boolean "requires_conference_pass", default: false, null: false
    t.datetime "sales_end_at"
    t.datetime "sales_start_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_ticket_types_on_slug", unique: true
  end

  create_table "tickets", force: :cascade do |t|
    t.string "attendee_email"
    t.string "attendee_name"
    t.datetime "canceled_at"
    t.json "checked_in_at", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "dietary_preference"
    t.integer "order_id", null: false
    t.integer "price_paise", null: false
    t.string "secret", null: false
    t.integer "ticket_type_id", null: false
    t.string "tshirt_size"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_tickets_on_order_id"
    t.index ["secret"], name: "index_tickets_on_secret", unique: true
    t.index ["ticket_type_id"], name: "index_tickets_on_ticket_type_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "coupons", "ticket_types"
  add_foreign_key "invoices", "invoices", column: "refers_to_id"
  add_foreign_key "invoices", "orders"
  add_foreign_key "orders", "coupons"
  add_foreign_key "payment_events", "orders"
  add_foreign_key "refunds", "orders"
  add_foreign_key "sessions", "admin_users"
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "ticket_types"
end
