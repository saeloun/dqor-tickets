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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_010000) do
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
    t.string "name"
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_admin_users_on_lower_email", unique: true
  end

  create_table "announcements", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "emailed_at"
    t.boolean "published", default: false, null: false
    t.datetime "published_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["published", "published_at"], name: "index_announcements_on_published_and_published_at"
  end

  create_table "connections", force: :cascade do |t|
    t.bigint "connected_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["connected_user_id"], name: "index_connections_on_connected_user_id"
    t.index ["user_id", "connected_user_id"], name: "index_connections_on_user_id_and_connected_user_id", unique: true
    t.index ["user_id"], name: "index_connections_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "one_last_read_at"
    t.bigint "participant_one_id", null: false
    t.bigint "participant_two_id", null: false
    t.datetime "two_last_read_at"
    t.datetime "updated_at", null: false
    t.index ["participant_one_id", "participant_two_id"], name: "idx_on_participant_one_id_participant_two_id_34e343b89f", unique: true
    t.index ["participant_one_id"], name: "index_conversations_on_participant_one_id"
    t.index ["participant_two_id"], name: "index_conversations_on_participant_two_id"
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

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.bigint "organization_id", null: false
    t.string "slug", null: false
    t.datetime "starts_at"
    t.string "status", default: "draft", null: false
    t.string "timezone", default: "UTC", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "slug"], name: "index_events_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.check_constraint "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "events_ordered_dates"
    t.check_constraint "status::text <> 'published'::text OR starts_at IS NOT NULL AND ends_at IS NOT NULL", name: "events_publication_dates"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying]::text[])", name: "events_valid_status"
  end

  create_table "faqs", force: :cascade do |t|
    t.text "answer"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.string "question", null: false
    t.datetime "updated_at", null: false
    t.index ["published", "position"], name: "index_faqs_on_published_and_position"
  end

  create_table "hiring_access_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["application_id"], name: "index_hiring_access_events_on_application_id"
    t.index ["user_id"], name: "index_hiring_access_events_on_user_id"
  end

  create_table "hiring_affiliations", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["company_id", "user_id"], name: "index_hiring_affiliations_on_company_id_and_user_id", unique: true
    t.index ["company_id"], name: "index_hiring_affiliations_on_company_id"
    t.index ["user_id"], name: "index_hiring_affiliations_on_user_id"
  end

  create_table "hiring_applications", force: :cascade do |t|
    t.bigint "applicant_id", null: false
    t.datetime "consented_at", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.binary "quarantined_pdf"
    t.string "resume_digest"
    t.string "scan_digest"
    t.string "scan_status", default: "quarantined", null: false
    t.datetime "scanned_at"
    t.bigint "share_request_id"
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.datetime "withdrawn_at"
    t.index ["applicant_id"], name: "index_hiring_applications_on_applicant_id"
    t.index ["job_id", "applicant_id"], name: "index_hiring_applications_on_job_id_and_applicant_id", unique: true
    t.index ["job_id"], name: "index_hiring_applications_on_job_id"
    t.index ["share_request_id"], name: "index_hiring_applications_on_share_request_id", unique: true
  end

  create_table "hiring_companies", force: :cascade do |t|
    t.bigint "claimant_id", null: false
    t.datetime "created_at", null: false
    t.text "evidence", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.bigint "reviewer_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "website", null: false
    t.index ["claimant_id"], name: "index_hiring_companies_on_claimant_id"
    t.index ["organization_id"], name: "index_hiring_companies_on_organization_id"
    t.index ["reviewer_id"], name: "index_hiring_companies_on_reviewer_id"
  end

  create_table "hiring_jobs", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.bigint "event_id"
    t.boolean "open", default: true, null: false
    t.bigint "recruiter_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_hiring_jobs_on_company_id"
    t.index ["event_id"], name: "index_hiring_jobs_on_event_id"
    t.index ["recruiter_id"], name: "index_hiring_jobs_on_recruiter_id"
  end

  create_table "hiring_share_requests", force: :cascade do |t|
    t.bigint "applicant_id"
    t.datetime "consented_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.bigint "recipient_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["applicant_id"], name: "index_hiring_share_requests_on_applicant_id"
    t.index ["job_id"], name: "index_hiring_share_requests_on_job_id"
    t.index ["recipient_id"], name: "index_hiring_share_requests_on_recipient_id"
    t.index ["token_digest"], name: "index_hiring_share_requests_on_token_digest", unique: true
  end

  create_table "info_pages", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_info_pages_on_slug", unique: true
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

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.string "role", default: "viewer", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organization_id", "user_id"], name: "index_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'editor'::character varying, 'viewer'::character varying]::text[])", name: "memberships_valid_role"
  end

  create_table "messages", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.bigint "sender_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
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

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
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

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
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

  create_table "speakers", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "github"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.integer "status", default: 0, null: false
    t.string "title"
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.index ["published", "position"], name: "index_speakers_on_published_and_position"
    t.index ["status"], name: "index_speakers_on_status"
  end

  create_table "sponsors", force: :cascade do |t|
    t.text "blurb"
    t.datetime "created_at", null: false
    t.string "logo_path"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.string "tier"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["published", "position"], name: "index_sponsors_on_published_and_position"
  end

  create_table "talk_bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "talk_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["talk_id"], name: "index_talk_bookmarks_on_talk_id"
    t.index ["user_id", "talk_id"], name: "index_talk_bookmarks_on_user_id_and_talk_id", unique: true
    t.index ["user_id"], name: "index_talk_bookmarks_on_user_id"
  end

  create_table "talk_feedbacks", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "rating", null: false
    t.bigint "talk_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["talk_id", "user_id"], name: "index_talk_feedbacks_on_talk_id_and_user_id", unique: true
    t.index ["talk_id"], name: "index_talk_feedbacks_on_talk_id"
    t.index ["user_id"], name: "index_talk_feedbacks_on_user_id"
  end

  create_table "talk_questions", force: :cascade do |t|
    t.datetime "answered_at"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "talk_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["talk_id", "created_at"], name: "index_talk_questions_on_talk_id_and_created_at"
    t.index ["talk_id"], name: "index_talk_questions_on_talk_id"
    t.index ["user_id"], name: "index_talk_questions_on_user_id"
  end

  create_table "talks", force: :cascade do |t|
    t.text "abstract"
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.string "room"
    t.text "speaker_bio"
    t.bigint "speaker_id"
    t.string "speaker_name"
    t.datetime "starts_at"
    t.string "title", null: false
    t.string "track"
    t.datetime "updated_at", null: false
    t.index ["published", "starts_at"], name: "index_talks_on_published_and_starts_at"
    t.index ["speaker_id"], name: "index_talks_on_speaker_id"
  end

  create_table "team_members", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "linkedin_url"
    t.string "name", null: false
    t.string "photo_url"
    t.integer "position", default: 0, null: false
    t.boolean "publicly_listed", default: true, null: false
    t.string "role"
    t.string "team"
    t.string "twitter_handle"
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_team_members_on_position"
    t.index ["publicly_listed"], name: "index_team_members_on_publicly_listed"
  end

  create_table "ticket_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "event_ends_on"
    t.date "event_starts_on"
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
    t.string "venue_address"
    t.string "venue_name"
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

  create_table "users", force: :cascade do |t|
    t.datetime "announcements_seen_at"
    t.text "bio"
    t.string "bluesky"
    t.datetime "created_at", null: false
    t.boolean "discoverable", default: true, null: false
    t.string "email", null: false
    t.string "github"
    t.string "linkedin"
    t.string "mastodon"
    t.string "name"
    t.string "password_digest"
    t.boolean "public_attendee", default: true, null: false
    t.string "referral_code"
    t.datetime "updated_at", null: false
    t.string "website"
    t.string "x_username"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["referral_code"], name: "index_users_on_referral_code", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "connections", "users"
  add_foreign_key "connections", "users", column: "connected_user_id"
  add_foreign_key "conversations", "users", column: "participant_one_id"
  add_foreign_key "conversations", "users", column: "participant_two_id"
  add_foreign_key "coupons", "ticket_types"
  add_foreign_key "events", "organizations"
  add_foreign_key "hiring_access_events", "hiring_applications", column: "application_id"
  add_foreign_key "hiring_access_events", "users"
  add_foreign_key "hiring_affiliations", "hiring_companies", column: "company_id"
  add_foreign_key "hiring_affiliations", "users"
  add_foreign_key "hiring_applications", "hiring_jobs", column: "job_id"
  add_foreign_key "hiring_applications", "hiring_share_requests", column: "share_request_id"
  add_foreign_key "hiring_applications", "users", column: "applicant_id"
  add_foreign_key "hiring_companies", "organizations"
  add_foreign_key "hiring_companies", "users", column: "claimant_id"
  add_foreign_key "hiring_companies", "users", column: "reviewer_id"
  add_foreign_key "hiring_jobs", "events"
  add_foreign_key "hiring_jobs", "hiring_companies", column: "company_id"
  add_foreign_key "hiring_jobs", "users", column: "recruiter_id"
  add_foreign_key "hiring_share_requests", "hiring_jobs", column: "job_id"
  add_foreign_key "hiring_share_requests", "users", column: "applicant_id"
  add_foreign_key "hiring_share_requests", "users", column: "recipient_id"
  add_foreign_key "invoices", "invoices", column: "refers_to_id"
  add_foreign_key "invoices", "orders"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "orders", "coupons"
  add_foreign_key "payment_events", "orders"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "refunds", "orders"
  add_foreign_key "sessions", "admin_users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "talk_bookmarks", "talks"
  add_foreign_key "talk_bookmarks", "users"
  add_foreign_key "talk_feedbacks", "talks"
  add_foreign_key "talk_feedbacks", "users"
  add_foreign_key "talk_questions", "talks"
  add_foreign_key "talk_questions", "users"
  add_foreign_key "talks", "speakers"
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "ticket_types"
end
