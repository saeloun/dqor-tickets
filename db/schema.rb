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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index "lower((email)::text)", name: "index_admin_users_on_lower_email", unique: true
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
    t.index "lower((code)::text)", name: "index_coupons_on_lower_code", unique: true
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
    t.index ["order_id"], name: "index_invoices_one_invoice_per_order", unique: true, where: "((kind)::text = 'invoice'::text)"
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
    t.string "level", default: "info", null: false
    t.string "mode"
    t.integer "order_id", null: false
    t.json "raw", default: {}, null: false
    t.string "razorpay_event_id", null: false
    t.string "razorpay_payment_id"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payment_events_on_order_id"
    t.index ["razorpay_event_id"], name: "index_payment_events_on_razorpay_event_id", unique: true
    t.index ["razorpay_payment_id"], name: "index_payment_events_on_razorpay_payment_id", unique: true, where: "(razorpay_payment_id IS NOT NULL)"
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
    t.index ["razorpay_refund_id"], name: "index_refunds_on_razorpay_refund_id", unique: true, where: "(razorpay_refund_id IS NOT NULL)"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["admin_user_id"], name: "index_sessions_on_admin_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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
    t.datetime "assigned_at"
    t.string "attendee_email"
    t.string "attendee_name"
    t.datetime "canceled_at"
    t.json "checked_in_at", default: {}, null: false
    t.boolean "childcare_needed", default: false, null: false
    t.string "claim_token"
    t.datetime "created_at", null: false
    t.string "dietary_preference"
    t.integer "order_id", null: false
    t.integer "price_paise", null: false
    t.string "secret", null: false
    t.integer "ticket_type_id", null: false
    t.string "tshirt_size"
    t.datetime "updated_at", null: false
    t.index ["claim_token"], name: "index_tickets_on_claim_token", unique: true
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
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "ticket_types"
end
