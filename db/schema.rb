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

ActiveRecord::Schema[8.1].define(version: 2026_07_29_176000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "billing_email"
    t.string "country", limit: 2, default: "IN", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
  end

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

  create_table "answers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id"
    t.bigint "question_id", null: false
    t.bigint "ticket_id"
    t.datetime "updated_at", null: false
    t.text "value"
    t.jsonb "value_json"
    t.index ["order_id"], name: "index_answers_on_order_id"
    t.index ["question_id", "order_id"], name: "index_answers_on_question_and_order", unique: true, where: "(order_id IS NOT NULL)"
    t.index ["question_id", "ticket_id"], name: "index_answers_on_question_and_ticket", unique: true, where: "(ticket_id IS NOT NULL)"
    t.index ["question_id"], name: "index_answers_on_question_id"
    t.index ["ticket_id"], name: "index_answers_on_ticket_id"
  end

  create_table "checkin_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_id"
    t.string "direction", default: "entry", null: false
    t.bigint "event_id", null: false
    t.string "failure_reason"
    t.bigint "operator_user_id"
    t.bigint "program_session_id"
    t.datetime "recorded_at"
    t.datetime "scanned_at"
    t.boolean "successful", default: true, null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_checkin_records_on_event_id"
    t.index ["operator_user_id"], name: "index_checkin_records_on_operator_user_id"
    t.index ["program_session_id"], name: "index_checkin_records_on_program_session_id"
    t.index ["ticket_id", "recorded_at"], name: "index_checkin_records_on_ticket_id_and_recorded_at"
    t.index ["ticket_id"], name: "index_checkin_records_on_ticket_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "discount_paise"
    t.bigint "event_id"
    t.integer "max_uses"
    t.integer "percent"
    t.integer "ticket_type_id"
    t.datetime "updated_at", null: false
    t.integer "uses_count", default: 0, null: false
    t.datetime "valid_from"
    t.datetime "valid_until"
    t.index "lower((code)::text)", name: "index_coupons_on_lower_code", unique: true
    t.index ["event_id", "code"], name: "index_coupons_on_event_id_and_code", unique: true
    t.index ["ticket_type_id"], name: "index_coupons_on_ticket_type_id"
  end

  create_table "email_sequence_sends", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "email_sequence_step_id", null: false
    t.bigint "registration_id", null: false
    t.datetime "sent_at"
    t.datetime "updated_at", null: false
    t.index ["email_sequence_step_id", "registration_id"], name: "index_sequence_sends_on_step_and_registration", unique: true
    t.index ["email_sequence_step_id"], name: "index_email_sequence_sends_on_email_sequence_step_id"
    t.index ["registration_id"], name: "index_email_sequence_sends_on_registration_id"
  end

  create_table "email_sequence_steps", force: :cascade do |t|
    t.jsonb "audience_filter", default: {}, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.bigint "event_id", null: false
    t.integer "offset_seconds", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.string "subject", null: false
    t.string "trigger_type", default: "on_registration", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_email_sequence_steps_on_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.jsonb "brand", default: {}, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "INR", null: false
    t.datetime "ends_at"
    t.string "format", default: "in_person", null: false
    t.boolean "guest_list_public", default: false, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.bigint "organizer_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.datetime "starts_at"
    t.string "status", default: "draft", null: false
    t.string "theme"
    t.string "timezone", default: "Asia/Kolkata", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.text "venue_address"
    t.string "venue_name"
    t.string "venue_state_code", limit: 2
    t.string "visibility", default: "public", null: false
    t.index ["organizer_id", "slug"], name: "index_events_on_organizer_id_and_slug", unique: true
    t.index ["organizer_id"], name: "index_events_on_organizer_id"
  end

  create_table "identities", force: :cascade do |t|
    t.jsonb "auth", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "invoice_sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fiscal_year", null: false
    t.integer "last_number", default: 0, null: false
    t.bigint "organizer_id", null: false
    t.string "series", null: false
    t.datetime "updated_at", null: false
    t.index ["organizer_id", "series", "fiscal_year"], name: "idx_on_organizer_id_series_fiscal_year_96e4f20fb0", unique: true
    t.index ["organizer_id"], name: "index_invoice_sequences_on_organizer_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.json "buyer_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.date "issued_on", null: false
    t.string "kind", default: "invoice", null: false
    t.json "line_items", default: [], null: false
    t.string "number", null: false
    t.integer "order_id", null: false
    t.bigint "organizer_id"
    t.integer "refers_to_id"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_invoices_on_event_id"
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["order_id"], name: "index_invoices_one_invoice_per_order", unique: true, where: "((kind)::text = 'invoice'::text)"
    t.index ["organizer_id"], name: "index_invoices_on_organizer_id"
    t.index ["refers_to_id"], name: "index_invoices_on_refers_to_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "organizer_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organizer_id", "user_id"], name: "index_memberships_on_organizer_id_and_user_id", unique: true
    t.index ["organizer_id"], name: "index_memberships_on_organizer_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "billing_state_code", limit: 2
    t.string "buyer_name", null: false
    t.string "buyer_phone"
    t.string "code", null: false
    t.string "country", default: "IN"
    t.integer "coupon_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.string "email", null: false
    t.bigint "event_id"
    t.datetime "expires_at"
    t.string "gateway", default: "razorpay", null: false
    t.string "gateway_reference"
    t.string "gst_legal_name"
    t.string "gstin"
    t.json "metadata", default: {}, null: false
    t.bigint "organizer_id"
    t.string "razorpay_order_id"
    t.integer "status", default: 0, null: false
    t.integer "total_paise", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_orders_on_code", unique: true
    t.index ["coupon_id"], name: "index_orders_on_coupon_id"
    t.index ["event_id", "code"], name: "index_orders_on_event_id_and_code", unique: true
    t.index ["gateway", "gateway_reference"], name: "index_orders_on_gateway_and_gateway_reference", unique: true
    t.index ["organizer_id"], name: "index_orders_on_organizer_id"
    t.index ["razorpay_order_id"], name: "index_orders_on_razorpay_order_id", unique: true
  end

  create_table "organizers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "default_currency", limit: 3, default: "INR", null: false
    t.string "default_timezone", default: "Asia/Kolkata", null: false
    t.text "description"
    t.string "entity_type"
    t.string "name", null: false
    t.string "pan"
    t.string "payout_mode", default: "direct", null: false
    t.string "razorpay_linked_account_id"
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.string "support_email"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_organizers_on_account_id"
    t.index ["slug"], name: "index_organizers_on_slug", unique: true
  end

  create_table "payment_events", force: :cascade do |t|
    t.integer "amount_paise", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.string "gateway", default: "razorpay", null: false
    t.string "gateway_event_id"
    t.string "gateway_payment_id"
    t.string "kind", null: false
    t.string "level", default: "info", null: false
    t.string "mode"
    t.integer "order_id", null: false
    t.json "raw", default: {}, null: false
    t.string "razorpay_event_id", null: false
    t.string "razorpay_payment_id"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_payment_events_on_event_id"
    t.index ["gateway", "gateway_event_id"], name: "index_payment_events_on_gateway_and_gateway_event_id", unique: true, where: "(gateway_event_id IS NOT NULL)"
    t.index ["gateway", "gateway_payment_id"], name: "index_payment_events_on_gateway_and_gateway_payment_id", unique: true, where: "(gateway_payment_id IS NOT NULL)"
    t.index ["order_id"], name: "index_payment_events_on_order_id"
    t.index ["razorpay_event_id"], name: "index_payment_events_on_razorpay_event_id", unique: true
    t.index ["razorpay_payment_id"], name: "index_payment_events_on_razorpay_payment_id", unique: true, where: "(razorpay_payment_id IS NOT NULL)"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_minor"
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "gateway", null: false
    t.string "gateway_payment_id"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "order_id", null: false
    t.string "status", default: "created", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id"
  end

  create_table "personal_schedule_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "program_session_id", null: false
    t.bigint "registration_id", null: false
    t.datetime "updated_at", null: false
    t.index ["program_session_id"], name: "index_personal_schedule_entries_on_program_session_id"
    t.index ["registration_id", "program_session_id"], name: "index_pse_on_registration_and_session", unique: true
    t.index ["registration_id"], name: "index_personal_schedule_entries_on_registration_id"
  end

  create_table "program_session_speakers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "program_session_id", null: false
    t.string "role", default: "speaker", null: false
    t.bigint "speaker_id", null: false
    t.datetime "updated_at", null: false
    t.index ["program_session_id", "speaker_id"], name: "index_pss_on_session_and_speaker", unique: true
    t.index ["program_session_id"], name: "index_program_session_speakers_on_program_session_id"
    t.index ["speaker_id"], name: "index_program_session_speakers_on_speaker_id"
  end

  create_table "program_sessions", force: :cascade do |t|
    t.text "abstract"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.bigint "event_id", null: false
    t.string "kind", default: "talk", null: false
    t.string "language"
    t.string "level"
    t.integer "max_attendees"
    t.integer "position", default: 0, null: false
    t.bigint "room_id"
    t.string "slides_url"
    t.datetime "starts_at"
    t.string "state", default: "confirmed", null: false
    t.string "title", null: false
    t.bigint "track_id"
    t.datetime "updated_at", null: false
    t.string "video_provider"
    t.string "video_url"
    t.index ["event_id"], name: "index_program_sessions_on_event_id"
    t.index ["room_id"], name: "index_program_sessions_on_room_id"
    t.index ["track_id"], name: "index_program_sessions_on_track_id"
  end

  create_table "questions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "answer_scope", default: "attendee", null: false
    t.integer "applies_to_ticket_type_ids", default: [], null: false, array: true
    t.string "ask_at", default: "checkout", null: false
    t.datetime "created_at", null: false
    t.bigint "dependency_question_id"
    t.jsonb "dependency_values", default: [], null: false
    t.bigint "event_id", null: false
    t.string "help_text"
    t.string "kind", default: "short_text", null: false
    t.string "label", null: false
    t.jsonb "options", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["dependency_question_id"], name: "index_questions_on_dependency_question_id"
    t.index ["event_id"], name: "index_questions_on_event_id"
  end

  create_table "refunds", force: :cascade do |t|
    t.integer "amount_paise", null: false
    t.datetime "created_at", null: false
    t.string "credit_note_number"
    t.bigint "event_id"
    t.string "gateway", default: "razorpay", null: false
    t.string "gateway_refund_id"
    t.integer "order_id", null: false
    t.string "razorpay_refund_id"
    t.string "status", null: false
    t.json "ticket_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_refunds_on_event_id"
    t.index ["gateway", "gateway_refund_id"], name: "index_refunds_on_gateway_and_gateway_refund_id", unique: true, where: "(gateway_refund_id IS NOT NULL)"
    t.index ["order_id"], name: "index_refunds_on_order_id"
    t.index ["razorpay_refund_id"], name: "index_refunds_on_razorpay_refund_id", unique: true, where: "(razorpay_refund_id IS NOT NULL)"
  end

  create_table "registrations", force: :cascade do |t|
    t.string "attendance_state", default: "interested", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "payment_state", default: "not_required", null: false
    t.string "source", default: "self", null: false
    t.bigint "ticket_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id", "user_id"], name: "index_registrations_on_event_id_and_user_id", unique: true
    t.index ["ticket_id"], name: "index_registrations_on_ticket_id"
    t.index ["user_id"], name: "index_registrations_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.text "accessibility_notes"
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "floor"
    t.boolean "is_virtual", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "stream_url"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_rooms_on_event_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "admin_user_id"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id"
    t.index ["admin_user_id"], name: "index_sessions_on_admin_user_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
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

  create_table "speakers", force: :cascade do |t|
    t.text "bio"
    t.string "bluesky"
    t.string "company"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "github"
    t.string "linkedin"
    t.string "mastodon"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "pronouns"
    t.string "speakerdeck"
    t.string "title"
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "website"
    t.index ["event_id"], name: "index_speakers_on_event_id"
    t.index ["user_id"], name: "index_speakers_on_user_id"
  end

  create_table "sponsor_orders", force: :cascade do |t|
    t.integer "amount_minor", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.text "notes"
    t.datetime "signed_at"
    t.bigint "sponsor_id", null: false
    t.bigint "sponsorship_tier_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["sponsor_id"], name: "index_sponsor_orders_on_sponsor_id"
    t.index ["sponsorship_tier_id"], name: "index_sponsor_orders_on_sponsorship_tier_id"
  end

  create_table "sponsors", force: :cascade do |t|
    t.string "badge"
    t.string "contact_email"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_type", default: "other", null: false
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.bigint "sponsorship_tier_id"
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["event_id", "slug"], name: "index_sponsors_on_event_id_and_slug", unique: true
    t.index ["event_id"], name: "index_sponsors_on_event_id"
    t.index ["sponsorship_tier_id"], name: "index_sponsors_on_sponsorship_tier_id"
  end

  create_table "sponsorship_tiers", force: :cascade do |t|
    t.jsonb "benefits", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.bigint "event_id", null: false
    t.integer "level", default: 0, null: false
    t.integer "max_slots"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_minor"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_sponsorship_tiers_on_event_id"
  end

  create_table "tax_profiles", force: :cascade do |t|
    t.text "address", null: false
    t.string "cn_prefix", null: false
    t.string "country", limit: 2, default: "IN", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.string "gstin"
    t.string "invoice_prefix", null: false
    t.string "invoice_timing", default: "immediate", null: false
    t.string "legal_name", null: false
    t.string "lut_number"
    t.bigint "organizer_id", null: false
    t.string "registered_state_code", limit: 2, null: false
    t.string "sac_code", default: "998596", null: false
    t.boolean "tax_inclusive", default: true, null: false
    t.integer "tax_rate_bp", default: 1800, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_tax_profiles_on_event_id"
    t.index ["organizer_id"], name: "index_tax_profiles_on_organizer_id"
  end

  create_table "ticket_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "event_id"
    t.boolean "hidden", default: false, null: false
    t.integer "max_per_order"
    t.integer "min_per_order", default: 1, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "prerequisite_ticket_type_id"
    t.integer "price_paise", null: false
    t.jsonb "prices_minor", default: {}, null: false
    t.boolean "requires_conference_pass", default: false, null: false
    t.datetime "sales_end_at"
    t.datetime "sales_start_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "slug"], name: "index_ticket_types_on_event_id_and_slug", unique: true
    t.index ["prerequisite_ticket_type_id"], name: "index_ticket_types_on_prerequisite_ticket_type_id"
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
    t.bigint "event_id"
    t.integer "order_id", null: false
    t.integer "price_paise", null: false
    t.string "secret", null: false
    t.integer "ticket_type_id", null: false
    t.string "tshirt_size"
    t.datetime "updated_at", null: false
    t.index ["claim_token"], name: "index_tickets_on_claim_token", unique: true
    t.index ["event_id"], name: "index_tickets_on_event_id"
    t.index ["order_id"], name: "index_tickets_on_order_id"
    t.index ["secret"], name: "index_tickets_on_secret", unique: true
    t.index ["ticket_type_id"], name: "index_tickets_on_ticket_type_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "text_color"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_tracks_on_event_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "github_login"
    t.string "name", null: false
    t.jsonb "preferences", default: {}, null: false
    t.string "timezone", default: "Asia/Kolkata", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "waitlist_entries", force: :cascade do |t|
    t.string "cancel_token"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "event_id", null: false
    t.string "name"
    t.datetime "offer_expires_at"
    t.string "offer_token"
    t.datetime "offered_at"
    t.bigint "order_id"
    t.integer "position"
    t.string "status", default: "waiting", null: false
    t.bigint "ticket_type_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["cancel_token"], name: "index_waitlist_entries_on_cancel_token", unique: true
    t.index ["event_id", "ticket_type_id", "email"], name: "index_waitlist_on_event_type_email", unique: true
    t.index ["event_id"], name: "index_waitlist_entries_on_event_id"
    t.index ["offer_token"], name: "index_waitlist_entries_on_offer_token", unique: true
    t.index ["order_id"], name: "index_waitlist_entries_on_order_id"
    t.index ["ticket_type_id"], name: "index_waitlist_entries_on_ticket_type_id"
    t.index ["user_id"], name: "index_waitlist_entries_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "answers", "orders"
  add_foreign_key "answers", "questions"
  add_foreign_key "answers", "tickets"
  add_foreign_key "checkin_records", "events"
  add_foreign_key "checkin_records", "program_sessions"
  add_foreign_key "checkin_records", "tickets"
  add_foreign_key "checkin_records", "users", column: "operator_user_id"
  add_foreign_key "coupons", "events", validate: false
  add_foreign_key "coupons", "ticket_types"
  add_foreign_key "email_sequence_sends", "email_sequence_steps"
  add_foreign_key "email_sequence_sends", "registrations"
  add_foreign_key "email_sequence_steps", "events"
  add_foreign_key "events", "organizers", validate: false
  add_foreign_key "identities", "users", validate: false
  add_foreign_key "invoice_sequences", "organizers", validate: false
  add_foreign_key "invoices", "events", validate: false
  add_foreign_key "invoices", "invoices", column: "refers_to_id"
  add_foreign_key "invoices", "orders"
  add_foreign_key "invoices", "organizers", validate: false
  add_foreign_key "memberships", "organizers", validate: false
  add_foreign_key "memberships", "users", validate: false
  add_foreign_key "orders", "coupons"
  add_foreign_key "orders", "events", validate: false
  add_foreign_key "orders", "organizers", validate: false
  add_foreign_key "organizers", "accounts", validate: false
  add_foreign_key "payment_events", "events", validate: false
  add_foreign_key "payment_events", "orders"
  add_foreign_key "payments", "orders"
  add_foreign_key "personal_schedule_entries", "program_sessions"
  add_foreign_key "personal_schedule_entries", "registrations"
  add_foreign_key "program_session_speakers", "program_sessions"
  add_foreign_key "program_session_speakers", "speakers"
  add_foreign_key "program_sessions", "events"
  add_foreign_key "program_sessions", "rooms"
  add_foreign_key "program_sessions", "tracks"
  add_foreign_key "questions", "events"
  add_foreign_key "questions", "questions", column: "dependency_question_id"
  add_foreign_key "refunds", "events", validate: false
  add_foreign_key "refunds", "orders"
  add_foreign_key "registrations", "events", validate: false
  add_foreign_key "registrations", "tickets", validate: false
  add_foreign_key "registrations", "users", validate: false
  add_foreign_key "rooms", "events"
  add_foreign_key "sessions", "admin_users"
  add_foreign_key "sessions", "users", validate: false
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "speakers", "events"
  add_foreign_key "speakers", "users"
  add_foreign_key "sponsor_orders", "sponsors"
  add_foreign_key "sponsor_orders", "sponsorship_tiers"
  add_foreign_key "sponsors", "events"
  add_foreign_key "sponsors", "sponsorship_tiers"
  add_foreign_key "sponsorship_tiers", "events"
  add_foreign_key "tax_profiles", "events", validate: false
  add_foreign_key "tax_profiles", "organizers", validate: false
  add_foreign_key "ticket_types", "events", validate: false
  add_foreign_key "ticket_types", "ticket_types", column: "prerequisite_ticket_type_id", validate: false
  add_foreign_key "tickets", "events", validate: false
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "ticket_types"
  add_foreign_key "tracks", "events"
  add_foreign_key "waitlist_entries", "events"
  add_foreign_key "waitlist_entries", "orders"
  add_foreign_key "waitlist_entries", "ticket_types"
  add_foreign_key "waitlist_entries", "users"
end
