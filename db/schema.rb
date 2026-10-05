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

ActiveRecord::Schema[8.1].define(version: 2026_10_05_110000) do
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

  create_table "announcement_campaigns", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.bigint "announcement_id", null: false
    t.datetime "approved_at", null: false
    t.integer "audience_count", null: false
    t.text "body", null: false
    t.string "content_digest", null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_announcement_campaigns_on_admin_user_id"
    t.index ["announcement_id"], name: "index_announcement_campaigns_on_announcement_id", unique: true
  end

  create_table "announcement_deliveries", force: :cascade do |t|
    t.bigint "announcement_campaign_id", null: false
    t.datetime "attempted_at"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "error_class"
    t.string "state", default: "pending", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["announcement_campaign_id", "email"], name: "unique_announcement_recipient", unique: true
    t.index ["announcement_campaign_id"], name: "index_announcement_deliveries_on_announcement_campaign_id"
    t.index ["state", "id"], name: "index_announcement_deliveries_on_state_and_id"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'preparing'::character varying, 'submitting'::character varying, 'submitted'::character varying, 'suppressed'::character varying, 'failed'::character varying, 'unknown'::character varying]::text[])", name: "announcement_delivery_state"
  end

  create_table "announcement_dispatch_limits", force: :cascade do |t|
    t.integer "used", default: 0, null: false
    t.datetime "window_started_at", null: false
  end

  create_table "announcement_preferences", force: :cascade do |t|
    t.string "consent_source"
    t.datetime "consented_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "suppressed_at"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_announcement_preferences_on_email", unique: true
    t.check_constraint "email::text = lower(btrim(email::text))", name: "announcement_email_normalized"
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

  create_table "chat_login_grants", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "name"
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_chat_login_grants_on_code_digest", unique: true
  end

  create_table "checkin_audits", force: :cascade do |t|
    t.bigint "admin_user_id"
    t.datetime "created_at", null: false
    t.date "event_date", null: false
    t.string "outcome", null: false
    t.string "source", null: false
    t.bigint "ticket_id"
    t.index ["admin_user_id"], name: "index_checkin_audits_on_admin_user_id"
    t.index ["event_date", "outcome"], name: "index_checkin_audits_on_event_date_and_outcome"
    t.index ["ticket_id"], name: "index_checkin_audits_on_ticket_id"
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

  create_table "event_branding_assets", force: :cascade do |t|
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.bigint "event_branding_setting_id", null: false
    t.integer "height", null: false
    t.binary "image_data", null: false
    t.datetime "updated_at", null: false
    t.integer "width", null: false
    t.index ["event_branding_setting_id"], name: "index_event_branding_assets_on_event_branding_setting_id"
  end

  create_table "event_branding_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "draft", default: {}, null: false
    t.string "event_key", default: "dqor", null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "previous_published"
    t.jsonb "published"
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.index ["event_key"], name: "index_event_branding_settings_on_event_key", unique: true
    t.index ["published_by_id"], name: "index_event_branding_settings_on_published_by_id"
    t.index ["updated_by_id"], name: "index_event_branding_settings_on_updated_by_id"
    t.check_constraint "event_key::text = 'dqor'::text", name: "event_branding_single_existing_event"
  end

  create_table "event_slot_redemptions", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.datetime "created_at", null: false
    t.bigint "event_slot_id", null: false
    t.datetime "redeemed_at", null: false
    t.string "request_key", null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.bigint "voided_by_id"
    t.index ["admin_user_id"], name: "index_event_slot_redemptions_on_admin_user_id"
    t.index ["event_slot_id", "request_key"], name: "index_event_slot_redemptions_on_event_slot_id_and_request_key", unique: true
    t.index ["event_slot_id"], name: "index_event_slot_redemptions_on_event_slot_id"
    t.index ["ticket_id"], name: "index_event_slot_redemptions_on_ticket_id"
  end

  create_table "event_slots", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.string "name", null: false
    t.integer "redemption_limit", default: 1, null: false
    t.datetime "starts_at", null: false
    t.bigint "ticket_type_ids", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.check_constraint "ends_at > starts_at AND redemption_limit > 0 AND (capacity IS NULL OR capacity > 0)", name: "event_slot_limits"
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

  create_table "free_checkins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_free_checkins_on_event_id"
    t.index ["operator_id"], name: "index_free_checkins_on_operator_id"
    t.index ["ticket_id"], name: "index_free_checkins_on_ticket_id", unique: true
  end

  create_table "free_event_form_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "form_id", null: false
    t.integer "number", null: false
    t.jsonb "questions", default: [], null: false
    t.bigint "ticket_type_id", null: false
    t.index ["form_id", "number"], name: "index_free_event_form_versions_on_form_id_and_number", unique: true
    t.index ["form_id"], name: "index_free_event_form_versions_on_form_id"
    t.index ["id", "event_id", "ticket_type_id"], name: "free_form_version_ownership", unique: true
  end

  create_table "free_event_forms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "draft_questions", default: [], null: false
    t.bigint "event_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "ticket_type_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_free_event_forms_on_event_id"
    t.index ["id", "event_id", "ticket_type_id"], name: "free_form_ownership", unique: true
    t.index ["ticket_type_id"], name: "index_free_event_forms_on_ticket_type_id", unique: true
  end

  create_table "free_event_responses", force: :cascade do |t|
    t.jsonb "answers", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "form_version_id", null: false
    t.bigint "ticket_id", null: false
    t.bigint "ticket_type_id", null: false
    t.index ["form_version_id"], name: "index_free_event_responses_on_form_version_id"
    t.index ["ticket_id"], name: "index_free_event_responses_on_ticket_id", unique: true
  end

  create_table "free_registration_windows", force: :cascade do |t|
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.datetime "draft_closes_at"
    t.datetime "draft_opens_at"
    t.string "draft_timezone", null: false
    t.bigint "event_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "opens_at"
    t.datetime "published_at"
    t.bigint "ticket_type_id", null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_free_registration_windows_on_event_id"
    t.index ["ticket_type_id"], name: "index_free_registration_windows_on_ticket_type_id", unique: true
    t.check_constraint "draft_opens_at IS NULL OR draft_closes_at IS NULL OR draft_opens_at < draft_closes_at", name: "free_window_draft_order"
    t.check_constraint "opens_at IS NULL OR closes_at IS NULL OR opens_at < closes_at", name: "free_window_published_order"
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

  create_table "invoice_policy_reviews", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "configured_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "policy_data", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.bigint "supersedes_id"
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_invoice_policy_reviews_on_approved_by_id"
    t.index ["created_by_id"], name: "index_invoice_policy_reviews_on_created_by_id"
    t.index ["supersedes_id"], name: "index_invoice_policy_reviews_on_supersedes_id"
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
    t.json "seller_snapshot"
    t.integer "snapshot_version"
    t.json "tax_snapshot"
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

  create_table "native_attendee_authorizations", force: :cascade do |t|
    t.string "callback_uri", null: false
    t.datetime "canceled_at"
    t.string "client_id", null: false
    t.string "code_challenge", null: false
    t.string "code_digest"
    t.datetime "code_expires_at"
    t.string "consent_digest"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "creation_digest", null: false
    t.string "email_request_digest"
    t.string "email_snapshot"
    t.datetime "expires_at", null: false
    t.string "password_fingerprint"
    t.string "state", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "verification_nonce_digest"
    t.datetime "verified_at"
    t.index ["code_digest"], name: "index_native_attendee_authorizations_on_code_digest", unique: true, where: "(code_digest IS NOT NULL)"
    t.index ["user_id"], name: "index_native_attendee_authorizations_on_user_id"
    t.check_constraint "(status <> ALL (ARRAY[1, 2, 3])) OR user_id IS NOT NULL AND email_snapshot IS NOT NULL AND password_fingerprint IS NOT NULL AND verified_at IS NOT NULL AND consent_digest IS NOT NULL", name: "native_attendee_verified_binding"
    t.check_constraint "(status <> ALL (ARRAY[2, 3])) OR code_digest IS NOT NULL AND code_expires_at IS NOT NULL", name: "native_attendee_code_binding"
    t.check_constraint "status = ANY (ARRAY[0, 1, 2, 3, 4, 5])", name: "native_attendee_authorization_status"
  end

  create_table "native_attendee_sessions", force: :cascade do |t|
    t.string "client_id", null: false
    t.datetime "created_at", null: false
    t.string "email_snapshot", null: false
    t.string "event", default: "dqor-2026", null: false
    t.datetime "expires_at", null: false
    t.bigint "native_attendee_authorization_id", null: false
    t.string "password_fingerprint", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["native_attendee_authorization_id"], name: "idx_on_native_attendee_authorization_id_527e7438fb", unique: true
    t.index ["token_digest"], name: "index_native_attendee_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_native_attendee_sessions_on_user_id"
    t.check_constraint "event::text = 'dqor-2026'::text", name: "native_attendee_session_event"
  end

  create_table "native_staff_sessions", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.jsonb "capabilities", default: [], null: false
    t.datetime "created_at", null: false
    t.string "event", null: false
    t.jsonb "event_dates", default: [], null: false
    t.datetime "expires_at", null: false
    t.string "password_fingerprint", null: false
    t.string "role", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_native_staff_sessions_on_admin_user_id"
    t.index ["expires_at"], name: "index_native_staff_sessions_on_expires_at"
    t.index ["token_digest"], name: "index_native_staff_sessions_on_token_digest", unique: true
  end

  create_table "operations_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.bigint "record_id", null: false
    t.string "record_kind", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["event_id"], name: "index_operations_audit_logs_on_event_id"
    t.index ["user_id"], name: "index_operations_audit_logs_on_user_id"
  end

  create_table "operations_business_contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.boolean "outreach_approved", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_operations_business_contacts_on_event_id"
  end

  create_table "operations_fulfillment_tasks", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.date "due_on"
    t.bigint "event_id", null: false
    t.bigint "sponsor_deal_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_operations_fulfillment_tasks_on_event_id"
    t.index ["sponsor_deal_id"], name: "index_operations_fulfillment_tasks_on_sponsor_deal_id"
  end

  create_table "operations_manual_entries", force: :cascade do |t|
    t.bigint "amount_paise", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "kind", null: false
    t.date "occurred_on", null: false
    t.string "reference", null: false
    t.bigint "sponsor_deal_id"
    t.datetime "updated_at", null: false
    t.bigint "vendor_engagement_id"
    t.index ["event_id"], name: "index_operations_manual_entries_on_event_id"
    t.index ["sponsor_deal_id"], name: "index_operations_manual_entries_on_sponsor_deal_id"
    t.index ["vendor_engagement_id"], name: "index_operations_manual_entries_on_vendor_engagement_id"
    t.check_constraint "amount_paise > 0", name: "manual_entries_positive_amount"
    t.check_constraint "sponsor_deal_id IS NOT NULL AND vendor_engagement_id IS NULL AND (kind::text = ANY (ARRAY['receipt'::character varying, 'refund'::character varying]::text[])) OR sponsor_deal_id IS NULL AND vendor_engagement_id IS NOT NULL AND (kind::text = ANY (ARRAY['expense'::character varying, 'expense_refund'::character varying]::text[]))", name: "manual_entry_target"
  end

  create_table "operations_sponsor_deals", force: :cascade do |t|
    t.bigint "amount_paise", null: false
    t.bigint "business_contact_id", null: false
    t.string "contribution", default: "cash", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "stage", default: "pledged", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["business_contact_id"], name: "index_operations_sponsor_deals_on_business_contact_id"
    t.index ["event_id"], name: "index_operations_sponsor_deals_on_event_id"
    t.check_constraint "(stage::text = ANY (ARRAY['pledged'::character varying, 'committed'::character varying]::text[])) AND (contribution::text = ANY (ARRAY['cash'::character varying, 'in_kind'::character varying]::text[]))", name: "sponsor_deal_categories"
    t.check_constraint "amount_paise > 0", name: "sponsor_deals_positive_amount"
  end

  create_table "operations_vendor_engagements", force: :cascade do |t|
    t.bigint "amount_paise", null: false
    t.bigint "business_contact_id", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["business_contact_id"], name: "index_operations_vendor_engagements_on_business_contact_id"
    t.index ["event_id"], name: "index_operations_vendor_engagements_on_event_id"
    t.check_constraint "amount_paise > 0", name: "vendor_engagements_positive_amount"
  end

  create_table "orders", force: :cascade do |t|
    t.string "billing_state_code", limit: 2
    t.string "buyer_name", null: false
    t.string "buyer_phone"
    t.string "code", null: false
    t.integer "coupon_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "event_id"
    t.datetime "expires_at"
    t.string "gst_legal_name"
    t.string "gstin"
    t.json "metadata", default: {}, null: false
    t.virtual "ownership_key", type: :bigint, as: "COALESCE(event_id, (0)::bigint)", stored: true
    t.string "razorpay_order_id"
    t.integer "status", default: 0, null: false
    t.integer "total_paise", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["code"], name: "index_orders_on_code", unique: true
    t.index ["coupon_id"], name: "index_orders_on_coupon_id"
    t.index ["event_id", "user_id"], name: "one_free_registration_per_event_user", unique: true, where: "(event_id IS NOT NULL)"
    t.index ["event_id"], name: "index_orders_on_event_id"
    t.index ["id", "ownership_key"], name: "index_orders_on_id_and_ownership_key", unique: true
    t.index ["razorpay_order_id"], name: "index_orders_on_razorpay_order_id", unique: true
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.check_constraint "event_id IS NULL OR event_id > 0", name: "orders_positive_event"
    t.check_constraint "event_id IS NULL OR user_id IS NOT NULL AND total_paise = 0 AND razorpay_order_id IS NULL AND coupon_id IS NULL", name: "owned_orders_free_only"
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
    t.bigint "event_id"
    t.date "event_starts_on"
    t.datetime "free_published_at"
    t.boolean "hidden", default: false, null: false
    t.integer "max_per_order"
    t.integer "min_per_order", default: 1, null: false
    t.string "name", null: false
    t.virtual "ownership_key", type: :bigint, as: "COALESCE(event_id, (0)::bigint)", stored: true
    t.integer "position", default: 0, null: false
    t.integer "price_paise", null: false
    t.boolean "requires_conference_pass", default: false, null: false
    t.datetime "sales_end_at"
    t.datetime "sales_start_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "venue_address"
    t.string "venue_name"
    t.index ["event_id"], name: "index_ticket_types_on_event_id"
    t.index ["id", "ownership_key"], name: "index_ticket_types_on_id_and_ownership_key", unique: true
    t.index ["slug"], name: "index_ticket_types_on_slug", unique: true
    t.check_constraint "event_id IS NULL OR event_id > 0", name: "ticket_types_positive_event"
    t.check_constraint "event_id IS NULL OR hidden = true AND active = false", name: "event_ticket_types_staged"
    t.check_constraint "free_published_at IS NULL OR event_id IS NOT NULL AND price_paise = 0 AND capacity IS NOT NULL AND capacity > 0", name: "free_inventory_publication"
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
    t.virtual "ownership_key", type: :bigint, as: "COALESCE(event_id, (0)::bigint)", stored: true
    t.integer "price_paise", null: false
    t.string "secret", null: false
    t.integer "ticket_type_id", null: false
    t.string "tshirt_size"
    t.datetime "updated_at", null: false
    t.index ["claim_token"], name: "index_tickets_on_claim_token", unique: true
    t.index ["event_id"], name: "index_tickets_on_event_id"
    t.index ["id", "ownership_key", "ticket_type_id"], name: "free_response_ticket_ownership_key", unique: true
    t.index ["id", "ownership_key"], name: "index_tickets_on_id_and_ownership_key", unique: true
    t.index ["order_id"], name: "index_tickets_on_order_id"
    t.index ["secret"], name: "index_tickets_on_secret", unique: true
    t.index ["ticket_type_id"], name: "index_tickets_on_ticket_type_id"
    t.check_constraint "event_id IS NULL OR event_id > 0", name: "tickets_positive_event"
    t.check_constraint "event_id IS NULL OR price_paise = 0", name: "owned_tickets_free_only"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "announcements_seen_at"
    t.text "bio"
    t.string "bluesky"
    t.datetime "created_at", null: false
    t.boolean "discoverable", default: true, null: false
    t.string "email", null: false
    t.boolean "free_pilot_identity", default: false, null: false
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
  add_foreign_key "announcement_campaigns", "admin_users"
  add_foreign_key "announcement_campaigns", "announcements"
  add_foreign_key "announcement_deliveries", "announcement_campaigns"
  add_foreign_key "checkin_audits", "admin_users", on_delete: :nullify
  add_foreign_key "checkin_audits", "tickets", on_delete: :nullify
  add_foreign_key "connections", "users"
  add_foreign_key "connections", "users", column: "connected_user_id"
  add_foreign_key "conversations", "users", column: "participant_one_id"
  add_foreign_key "conversations", "users", column: "participant_two_id"
  add_foreign_key "coupons", "ticket_types"
  add_foreign_key "event_branding_assets", "event_branding_settings"
  add_foreign_key "event_branding_settings", "admin_users", column: "published_by_id"
  add_foreign_key "event_branding_settings", "admin_users", column: "updated_by_id"
  add_foreign_key "event_slot_redemptions", "admin_users"
  add_foreign_key "event_slot_redemptions", "admin_users", column: "voided_by_id"
  add_foreign_key "event_slot_redemptions", "event_slots"
  add_foreign_key "event_slot_redemptions", "tickets"
  add_foreign_key "events", "organizations"
  add_foreign_key "free_checkins", "events"
  add_foreign_key "free_checkins", "tickets"
  add_foreign_key "free_checkins", "tickets", column: ["ticket_id", "event_id"], primary_key: ["id", "ownership_key"], name: "free_checkin_ticket_event"
  add_foreign_key "free_checkins", "users", column: "operator_id"
  add_foreign_key "free_event_form_versions", "free_event_forms", column: "form_id"
  add_foreign_key "free_event_form_versions", "free_event_forms", column: ["form_id", "event_id", "ticket_type_id"], primary_key: ["id", "event_id", "ticket_type_id"], name: "free_version_form_ownership"
  add_foreign_key "free_event_forms", "events"
  add_foreign_key "free_event_forms", "ticket_types"
  add_foreign_key "free_event_forms", "ticket_types", column: ["ticket_type_id", "event_id"], primary_key: ["id", "ownership_key"], name: "free_form_type_ownership"
  add_foreign_key "free_event_responses", "free_event_form_versions", column: "form_version_id"
  add_foreign_key "free_event_responses", "free_event_form_versions", column: ["form_version_id", "event_id", "ticket_type_id"], primary_key: ["id", "event_id", "ticket_type_id"], name: "free_response_version_ownership"
  add_foreign_key "free_event_responses", "tickets"
  add_foreign_key "free_event_responses", "tickets", column: ["ticket_id", "event_id", "ticket_type_id"], primary_key: ["id", "ownership_key", "ticket_type_id"], name: "free_response_ticket_ownership"
  add_foreign_key "free_registration_windows", "events"
  add_foreign_key "free_registration_windows", "ticket_types"
  add_foreign_key "free_registration_windows", "ticket_types", column: ["ticket_type_id", "event_id"], primary_key: ["id", "ownership_key"], name: "free_window_type_ownership"
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
  add_foreign_key "invoice_policy_reviews", "admin_users", column: "approved_by_id"
  add_foreign_key "invoice_policy_reviews", "admin_users", column: "created_by_id"
  add_foreign_key "invoice_policy_reviews", "invoice_policy_reviews", column: "supersedes_id"
  add_foreign_key "invoices", "invoices", column: "refers_to_id"
  add_foreign_key "invoices", "orders"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "native_attendee_authorizations", "users", on_delete: :cascade
  add_foreign_key "native_attendee_sessions", "native_attendee_authorizations", on_delete: :cascade
  add_foreign_key "native_attendee_sessions", "users", on_delete: :cascade
  add_foreign_key "native_staff_sessions", "admin_users", on_delete: :cascade
  add_foreign_key "operations_audit_logs", "events"
  add_foreign_key "operations_audit_logs", "users"
  add_foreign_key "operations_business_contacts", "events"
  add_foreign_key "operations_fulfillment_tasks", "events"
  add_foreign_key "operations_fulfillment_tasks", "operations_sponsor_deals", column: "sponsor_deal_id"
  add_foreign_key "operations_manual_entries", "events"
  add_foreign_key "operations_manual_entries", "operations_sponsor_deals", column: "sponsor_deal_id"
  add_foreign_key "operations_manual_entries", "operations_vendor_engagements", column: "vendor_engagement_id"
  add_foreign_key "operations_sponsor_deals", "events"
  add_foreign_key "operations_sponsor_deals", "operations_business_contacts", column: "business_contact_id"
  add_foreign_key "operations_vendor_engagements", "events"
  add_foreign_key "operations_vendor_engagements", "operations_business_contacts", column: "business_contact_id"
  add_foreign_key "orders", "coupons"
  add_foreign_key "orders", "events"
  add_foreign_key "orders", "users"
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
  add_foreign_key "ticket_types", "events"
  add_foreign_key "tickets", "events"
  add_foreign_key "tickets", "orders"
  add_foreign_key "tickets", "orders", column: ["order_id", "ownership_key"], primary_key: ["id", "ownership_key"], name: "tickets_order_ownership"
  add_foreign_key "tickets", "ticket_types"
  add_foreign_key "tickets", "ticket_types", column: ["ticket_type_id", "ownership_key"], primary_key: ["id", "ownership_key"], name: "tickets_type_ownership"
end
