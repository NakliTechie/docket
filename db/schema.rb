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

ActiveRecord::Schema[8.1].define(version: 2026_08_02_160000) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "tenant_id"
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
    t.index ["tenant_id"], name: "index_action_mailbox_inbound_emails_on_tenant_id"
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

  create_table "activities", force: :cascade do |t|
    t.text "body"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "due_at"
    t.integer "kind", default: 0, null: false
    t.integer "owner_id"
    t.integer "status", default: 0, null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.integer "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_activities_on_owner_id"
    t.index ["subject_type", "subject_id"], name: "index_activities_on_subject"
    t.index ["tenant_id", "owner_id", "status", "due_at"], name: "idx_on_tenant_id_owner_id_status_due_at_de7fa807ae"
    t.index ["tenant_id", "subject_type", "subject_id"], name: "index_activities_on_tenant_id_and_subject_type_and_subject_id"
    t.index ["tenant_id"], name: "index_activities_on_tenant_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "approval_processes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "tenant_id", null: false
    t.string "trigger_key", null: false
    t.integer "trigger_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "trigger_type", "trigger_key"], name: "index_approval_processes_on_tenant_and_trigger", unique: true
    t.index ["tenant_id"], name: "index_approval_processes_on_tenant_id"
  end

  create_table "approval_requests", force: :cascade do |t|
    t.integer "approval_process_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.integer "decided_by_id"
    t.text "reason"
    t.string "requested_action"
    t.integer "requested_by_id"
    t.integer "status", default: 0, null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_process_id"], name: "index_approval_requests_on_approval_process_id"
    t.index ["decided_by_id"], name: "index_approval_requests_on_decided_by_id"
    t.index ["requested_by_id"], name: "index_approval_requests_on_requested_by_id"
    t.index ["subject_type", "subject_id"], name: "index_approval_requests_on_subject"
    t.index ["tenant_id", "status"], name: "index_approval_requests_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_approval_requests_on_tenant_id"
  end

  create_table "audit_entries", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.string "actor_type"
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.json "changeset"
    t.datetime "created_at", null: false
    t.json "metadata"
    t.string "previous_sha", limit: 64, null: false
    t.datetime "redacted_at"
    t.integer "redaction_event_id"
    t.string "sha", limit: 64, null: false
    t.integer "tenant_id"
    t.index ["action"], name: "index_audit_entries_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_entries_on_actor"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_entries_on_auditable"
    t.index ["created_at"], name: "index_audit_entries_on_created_at"
    t.index ["redaction_event_id"], name: "index_audit_entries_on_redaction_event_id"
    t.index ["sha"], name: "index_audit_entries_on_sha", unique: true
    t.index ["tenant_id"], name: "index_audit_entries_on_tenant_id"
  end

  create_table "business_calendar_exceptions", force: :cascade do |t|
    t.bigint "business_calendar_id", null: false
    t.boolean "closed", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "ends_minute"
    t.string "name", null: false
    t.date "on_date", null: false
    t.integer "starts_minute"
    t.datetime "updated_at", null: false
    t.index ["business_calendar_id", "on_date"], name: "index_business_calendar_exceptions_unique", unique: true
    t.index ["business_calendar_id"], name: "index_business_calendar_exceptions_on_business_calendar_id"
    t.check_constraint "closed = true AND starts_minute IS NULL AND ends_minute IS NULL OR closed = false AND starts_minute >= 0 AND ends_minute <= 1440 AND starts_minute < ends_minute", name: "business_calendar_exceptions_shape_valid"
  end

  create_table "business_calendar_windows", force: :cascade do |t|
    t.bigint "business_calendar_id", null: false
    t.datetime "created_at", null: false
    t.integer "ends_minute", null: false
    t.integer "starts_minute", null: false
    t.datetime "updated_at", null: false
    t.integer "weekday", null: false
    t.index ["business_calendar_id", "weekday", "starts_minute", "ends_minute"], name: "index_business_calendar_windows_unique", unique: true
    t.index ["business_calendar_id"], name: "index_business_calendar_windows_on_business_calendar_id"
    t.check_constraint "starts_minute >= 0 AND ends_minute <= 1440 AND starts_minute < ends_minute", name: "business_calendar_windows_minutes_valid"
    t.check_constraint "weekday >= 0 AND weekday <= 6", name: "business_calendar_windows_weekday_valid"
  end

  create_table "business_calendars", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.bigint "tenant_id", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_business_calendars_on_tenant_id"
    t.index ["tenant_id"], name: "index_business_calendars_one_default", unique: true, where: "(is_default = true)"
  end

  create_table "campaigns", force: :cascade do |t|
    t.bigint "budget_cents", default: 0, null: false
    t.integer "channel", default: 5, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.date "ends_on"
    t.string "name", null: false
    t.date "starts_on"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "utm_campaign", null: false
    t.string "utm_medium"
    t.string "utm_source"
    t.index ["deleted_at"], name: "index_campaigns_on_deleted_at"
    t.index ["tenant_id", "code"], name: "index_live_campaigns_on_tenant_and_code", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id", "utm_campaign"], name: "index_live_campaigns_on_tenant_and_utm", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_campaigns_on_tenant_id"
    t.check_constraint "budget_cents >= 0", name: "campaigns_budget_non_negative"
    t.check_constraint "ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on", name: "campaigns_valid_date_window"
  end

  create_table "case_presences", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_seen_at", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["case_id"], name: "index_case_presences_on_case_id"
    t.index ["tenant_id", "case_id", "last_seen_at"], name: "index_case_presences_on_tenant_id_and_case_id_and_last_seen_at"
    t.index ["tenant_id", "case_id", "user_id"], name: "index_case_presences_on_tenant_id_and_case_id_and_user_id", unique: true
    t.index ["tenant_id"], name: "index_case_presences_on_tenant_id"
    t.index ["user_id"], name: "index_case_presences_on_user_id"
  end

  create_table "cases", force: :cascade do |t|
    t.integer "assignee_id"
    t.integer "category_id"
    t.integer "channel", default: 0, null: false
    t.datetime "closed_at"
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.json "custom_fields", default: {}, null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "external_id"
    t.datetime "first_responded_at"
    t.boolean "first_response_breached", default: false, null: false
    t.datetime "first_response_due_at"
    t.json "labels"
    t.integer "lock_version", default: 0, null: false
    t.datetime "merged_at"
    t.bigint "merged_into_id"
    t.integer "priority", default: 1, null: false
    t.integer "queue_id"
    t.integer "reopen_count", default: 0, null: false
    t.datetime "reopened_at"
    t.boolean "resolution_breached", default: false, null: false
    t.datetime "resolution_due_at"
    t.datetime "resolution_paused_at"
    t.integer "resolution_remaining_minutes"
    t.datetime "resolved_at"
    t.integer "routed_by_rule_id"
    t.integer "sla_policy_id"
    t.integer "source_connector_id"
    t.string "source_thread_id"
    t.integer "status", default: 0, null: false
    t.datetime "status_changed_at", null: false
    t.string "subject", null: false
    t.integer "tenant_id", null: false
    t.string "tracking_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_cases_on_assignee_id"
    t.index ["category_id"], name: "index_cases_on_category_id"
    t.index ["contact_id"], name: "index_cases_on_contact_id"
    t.index ["created_at"], name: "index_cases_on_created_at"
    t.index ["deleted_at"], name: "index_cases_on_deleted_at"
    t.index ["external_id"], name: "index_cases_on_external_id"
    t.index ["first_response_breached", "first_response_due_at"], name: "idx_on_first_response_breached_first_response_due_a_66b2255ab2"
    t.index ["merged_into_id"], name: "index_cases_on_merged_into_id"
    t.index ["priority"], name: "index_cases_on_priority"
    t.index ["queue_id"], name: "index_cases_on_queue_id"
    t.index ["resolution_breached", "resolution_due_at"], name: "index_cases_on_resolution_breached_and_resolution_due_at"
    t.index ["routed_by_rule_id"], name: "index_cases_on_routed_by_rule_id"
    t.index ["sla_policy_id"], name: "index_cases_on_sla_policy_id"
    t.index ["source_connector_id"], name: "index_cases_on_source_connector_id"
    t.index ["status", "queue_id"], name: "index_cases_on_status_and_queue_id"
    t.index ["status", "status_changed_at"], name: "index_cases_on_status_and_status_changed_at"
    t.index ["status"], name: "index_cases_on_status"
    t.index ["tenant_id", "merged_into_id"], name: "index_cases_on_tenant_id_and_merged_into_id"
    t.index ["tenant_id", "source_connector_id", "source_thread_id"], name: "index_cases_on_tenant_connector_thread"
    t.index ["tenant_id", "tracking_id"], name: "index_cases_on_tenant_id_and_tracking_id", unique: true
    t.index ["tenant_id"], name: "index_cases_on_tenant_id"
    t.check_constraint "resolution_remaining_minutes >= 0", name: "cases_resolution_remaining_minutes_nonnegative"
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "ai_auto_resolve", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_categories_on_deleted_at"
    t.index ["tenant_id", "name"], name: "index_categories_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_categories_on_tenant_id"
  end

  create_table "competitors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.text "notes"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["tenant_id", "name"], name: "index_competitors_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_competitors_on_tenant_id"
  end

  create_table "connector_invocations", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.json "args"
    t.integer "connector_id", null: false
    t.datetime "created_at", null: false
    t.string "decision_class"
    t.text "decision_reason"
    t.string "delegation_id"
    t.string "effect"
    t.text "error"
    t.datetime "finished_at"
    t.string "idempotency_key"
    t.string "on_behalf_of"
    t.text "reasoning"
    t.integer "requested_by_id"
    t.string "requested_by_type"
    t.json "result"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_connector_invocations_on_approved_by_id"
    t.index ["connector_id", "id"], name: "index_connector_invocations_on_connector_id_and_id"
    t.index ["connector_id", "idempotency_key"], name: "index_connector_invocations_idempotency", unique: true
    t.index ["connector_id"], name: "index_connector_invocations_on_connector_id"
    t.index ["delegation_id"], name: "index_connector_invocations_on_delegation_id", unique: true
    t.index ["requested_by_type", "requested_by_id"], name: "index_connector_invocations_on_requested_by"
    t.index ["tenant_id"], name: "index_connector_invocations_on_tenant_id"
  end

  create_table "connector_runs", force: :cascade do |t|
    t.integer "connector_id", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "finished_at"
    t.integer "records_created", default: 0, null: false
    t.integer "records_in", default: 0, null: false
    t.integer "records_updated", default: 0, null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.integer "trigger", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["connector_id", "id"], name: "index_connector_runs_on_connector_id_and_id"
    t.index ["connector_id"], name: "index_connector_runs_on_connector_id"
    t.index ["connector_id"], name: "index_connector_runs_on_one_running_per_connector", unique: true, where: "status = 0"
    t.index ["tenant_id"], name: "index_connector_runs_on_tenant_id"
  end

  create_table "connectors", force: :cascade do |t|
    t.integer "action_budget"
    t.integer "action_budget_window_minutes"
    t.json "auto_approve_actions"
    t.json "config"
    t.datetime "created_at", null: false
    t.text "credentials"
    t.datetime "deleted_at"
    t.json "enabled_actions"
    t.json "field_mapping"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.text "oauth_credentials"
    t.string "provider", null: false
    t.integer "schedule_interval_minutes"
    t.integer "shared_credential_id"
    t.integer "status", default: 0, null: false
    t.string "target", default: "contacts", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["deleted_at"], name: "index_connectors_on_deleted_at"
    t.index ["shared_credential_id"], name: "index_connectors_on_shared_credential_id"
    t.index ["status"], name: "index_connectors_on_status"
    t.index ["tenant_id"], name: "index_connectors_on_tenant_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.boolean "email_consent", default: false, null: false
    t.datetime "email_unsubscribed_at"
    t.datetime "erased_at"
    t.string "erasure_token"
    t.string "external_id"
    t.string "name", null: false
    t.text "notes"
    t.integer "organisation_id"
    t.string "phone"
    t.string "preferred_language", default: "en", null: false
    t.boolean "sms_consent", default: false, null: false
    t.integer "source_connector_id"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_contacts_on_deleted_at"
    t.index ["email"], name: "index_contacts_on_email"
    t.index ["organisation_id"], name: "index_contacts_on_organisation_id"
    t.index ["phone"], name: "index_contacts_on_phone"
    t.index ["source_connector_id"], name: "index_contacts_on_source_connector_id"
    t.index ["tenant_id", "erasure_token"], name: "index_contacts_on_tenant_id_and_erasure_token", unique: true, where: "(erasure_token IS NOT NULL)"
    t.index ["tenant_id", "external_id"], name: "index_contacts_on_tenant_id_and_external_id", unique: true, where: "((external_id IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["tenant_id"], name: "index_contacts_on_tenant_id"
  end

  create_table "csat_surveys", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.text "comment"
    t.bigint "contact_id"
    t.datetime "created_at", null: false
    t.integer "delivery_attempts", default: 0, null: false
    t.datetime "delivery_claimed_at"
    t.datetime "delivery_enqueued_at"
    t.text "delivery_last_error"
    t.integer "delivery_status", default: 0, null: false
    t.datetime "invited_at", null: false
    t.datetime "responded_at"
    t.integer "score"
    t.datetime "sent_at"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_csat_surveys_on_case_id"
    t.index ["contact_id"], name: "index_csat_surveys_on_contact_id"
    t.index ["tenant_id", "case_id"], name: "index_csat_surveys_on_tenant_id_and_case_id", unique: true
    t.index ["tenant_id", "delivery_status"], name: "index_csat_surveys_on_tenant_id_and_delivery_status"
    t.index ["tenant_id", "responded_at"], name: "index_csat_surveys_on_tenant_id_and_responded_at"
    t.index ["tenant_id"], name: "index_csat_surveys_on_tenant_id"
    t.check_constraint "score IS NULL OR score >= 1 AND score <= 5", name: "csat_surveys_score_valid"
  end

  create_table "custom_field_definitions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "field_type", null: false
    t.string "key", null: false
    t.string "label", null: false
    t.json "options", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "reportable", default: true, null: false
    t.boolean "required", default: false, null: false
    t.string "resource_type", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "resource_type", "key"], name: "index_custom_fields_on_tenant_resource_key", unique: true
    t.index ["tenant_id", "resource_type", "position"], name: "index_custom_fields_on_tenant_resource_position"
    t.index ["tenant_id"], name: "index_custom_field_definitions_on_tenant_id"
  end

  create_table "deal_competitors", force: :cascade do |t|
    t.bigint "competitor_id", null: false
    t.datetime "created_at", null: false
    t.bigint "deal_id", null: false
    t.integer "disposition", default: 0, null: false
    t.text "notes"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["competitor_id"], name: "index_deal_competitors_on_competitor_id"
    t.index ["deal_id"], name: "index_deal_competitors_on_deal_id"
    t.index ["tenant_id", "deal_id", "competitor_id"], name: "idx_on_tenant_id_deal_id_competitor_id_e0499f3a34", unique: true
    t.index ["tenant_id"], name: "index_deal_competitors_on_tenant_id"
  end

  create_table "deal_contact_roles", force: :cascade do |t|
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.integer "deal_id", null: false
    t.integer "role", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_deal_contact_roles_on_contact_id"
    t.index ["deal_id"], name: "index_deal_contact_roles_on_deal_id"
    t.index ["tenant_id", "deal_id", "contact_id"], name: "idx_on_tenant_id_deal_id_contact_id_32b9f19b5f", unique: true
    t.index ["tenant_id"], name: "index_deal_contact_roles_on_tenant_id"
  end

  create_table "deal_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.bigint "deal_id", null: false
    t.string "description", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.bigint "tenant_id", null: false
    t.bigint "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["deal_id"], name: "index_deal_line_items_on_deal_id"
    t.index ["product_id"], name: "index_deal_line_items_on_product_id"
    t.index ["tenant_id", "deal_id", "product_id"], name: "index_deal_line_items_on_tenant_id_and_deal_id_and_product_id", unique: true
    t.index ["tenant_id"], name: "index_deal_line_items_on_tenant_id"
  end

  create_table "deals", force: :cascade do |t|
    t.datetime "closed_at"
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.datetime "deleted_at"
    t.date "expected_close_on"
    t.string "external_id"
    t.datetime "first_touch_at"
    t.integer "first_touch_campaign_id"
    t.text "first_touch_landing_page"
    t.text "first_touch_referrer"
    t.string "first_touch_utm_campaign"
    t.string "first_touch_utm_content"
    t.string "first_touch_utm_medium"
    t.string "first_touch_utm_source"
    t.string "first_touch_utm_term"
    t.json "labels"
    t.integer "lead_id"
    t.integer "lost_reason"
    t.string "name", null: false
    t.integer "organisation_id"
    t.integer "owner_id"
    t.integer "pipeline_id", null: false
    t.integer "pipeline_stage_id", null: false
    t.integer "price_book_id"
    t.integer "source_connector_id"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "value_cents"
    t.index ["contact_id"], name: "index_deals_on_contact_id"
    t.index ["deleted_at"], name: "index_deals_on_deleted_at"
    t.index ["external_id"], name: "index_deals_on_external_id"
    t.index ["first_touch_campaign_id"], name: "index_deals_on_first_touch_campaign_id"
    t.index ["lead_id"], name: "index_deals_on_lead_id"
    t.index ["organisation_id"], name: "index_deals_on_organisation_id"
    t.index ["owner_id"], name: "index_deals_on_owner_id"
    t.index ["pipeline_id", "pipeline_stage_id"], name: "index_deals_on_pipeline_id_and_pipeline_stage_id"
    t.index ["pipeline_id"], name: "index_deals_on_pipeline_id"
    t.index ["pipeline_stage_id"], name: "index_deals_on_pipeline_stage_id"
    t.index ["price_book_id"], name: "index_deals_on_price_book_id"
    t.index ["source_connector_id"], name: "index_deals_on_source_connector_id"
    t.index ["status"], name: "index_deals_on_status"
    t.index ["tenant_id"], name: "index_deals_on_tenant_id"
  end

  create_table "decision_appeals", force: :cascade do |t|
    t.integer "appellant_id"
    t.datetime "created_at", null: false
    t.integer "decision_id", null: false
    t.text "grounds", null: false
    t.text "resolution"
    t.datetime "resolved_at"
    t.integer "reviewed_by_id"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["appellant_id"], name: "index_decision_appeals_on_appellant_id"
    t.index ["decision_id"], name: "index_decision_appeals_on_decision_id"
    t.index ["reviewed_by_id"], name: "index_decision_appeals_on_reviewed_by_id"
    t.index ["tenant_id"], name: "index_decision_appeals_on_tenant_id"
  end

  create_table "decisions", force: :cascade do |t|
    t.string "action", default: "label", null: false
    t.json "action_params"
    t.integer "approved_by_id"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.string "decision_class", null: false
    t.text "decision_reason"
    t.string "effect"
    t.text "reasoning"
    t.text "recommendation"
    t.string "rule", null: false
    t.string "signal", null: false
    t.integer "status", default: 0, null: false
    t.integer "subject_id", null: false
    t.string "subject_label"
    t.string "subject_type", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["rule", "subject_type", "subject_id"], name: "index_decisions_on_rule_and_subject_type_and_subject_id"
    t.index ["status"], name: "index_decisions_on_status"
    t.index ["subject_type", "subject_id"], name: "index_decisions_on_subject_type_and_subject_id"
    t.index ["tenant_id", "rule", "subject_type", "subject_id"], name: "index_decisions_unique_per_tenant_rule_subject", unique: true
    t.index ["tenant_id"], name: "index_decisions_on_tenant_id"
  end

  create_table "deliverable_studies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "deliverable_id", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "work_item_id", null: false
    t.index ["deliverable_id", "work_item_id"], name: "index_deliverable_studies_uniqueness", unique: true
    t.index ["deliverable_id"], name: "index_deliverable_studies_on_deliverable_id"
    t.index ["tenant_id"], name: "index_deliverable_studies_on_tenant_id"
    t.index ["work_item_id"], name: "index_deliverable_studies_on_work_item_id"
  end

  create_table "deliverables", force: :cascade do |t|
    t.text "approval_reason"
    t.integer "approved_by_id"
    t.datetime "created_at", null: false
    t.integer "deal_id", null: false
    t.datetime "deleted_at"
    t.datetime "issued_at"
    t.integer "project_id"
    t.json "scope_items", default: [], null: false
    t.integer "status", default: 0, null: false
    t.integer "submitted_by_id"
    t.text "summary"
    t.integer "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_deliverables_on_approved_by_id"
    t.index ["deal_id"], name: "index_deliverables_on_deal_id"
    t.index ["project_id"], name: "index_deliverables_on_project_id"
    t.index ["submitted_by_id"], name: "index_deliverables_on_submitted_by_id"
    t.index ["tenant_id", "deal_id"], name: "index_deliverables_on_tenant_id_and_deal_id"
    t.index ["tenant_id", "status"], name: "index_deliverables_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_deliverables_on_tenant_id"
  end

  create_table "entitlements", force: :cascade do |t|
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "ends_at"
    t.string "name", null: false
    t.integer "organisation_id"
    t.integer "sla_policy_id", null: false
    t.datetime "starts_at", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_entitlements_on_contact_id"
    t.index ["deleted_at"], name: "index_entitlements_on_deleted_at"
    t.index ["organisation_id"], name: "index_entitlements_on_organisation_id"
    t.index ["sla_policy_id"], name: "index_entitlements_on_sla_policy_id"
    t.index ["tenant_id", "contact_id", "starts_at"], name: "index_live_entitlements_on_contact_coverage", where: "deleted_at IS NULL"
    t.index ["tenant_id", "name"], name: "index_live_entitlements_on_tenant_and_name", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id", "organisation_id", "starts_at"], name: "index_live_entitlements_on_org_coverage", where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_entitlements_on_tenant_id"
    t.check_constraint "((contact_id IS NOT NULL AND organisation_id IS NULL) OR (contact_id IS NULL AND organisation_id IS NOT NULL))", name: "entitlements_exactly_one_holder"
    t.check_constraint "ends_at IS NULL OR ends_at > starts_at", name: "entitlements_valid_coverage_window"
  end

  create_table "escalation_executions", force: :cascade do |t|
    t.integer "case_id", null: false
    t.datetime "created_at", null: false
    t.integer "escalation_level_id", null: false
    t.datetime "executed_at", null: false
    t.datetime "reference_at", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_escalation_executions_on_case_id"
    t.index ["escalation_level_id", "case_id", "reference_at"], name: "index_escalation_executions_idempotency", unique: true
    t.index ["escalation_level_id"], name: "index_escalation_executions_on_escalation_level_id"
    t.index ["tenant_id"], name: "index_escalation_executions_on_tenant_id"
  end

  create_table "escalation_levels", force: :cascade do |t|
    t.integer "after_minutes", null: false
    t.datetime "created_at", null: false
    t.integer "escalation_rule_id", null: false
    t.integer "notify_user_id"
    t.integer "position", default: 0, null: false
    t.integer "tenant_id", null: false
    t.integer "then_assignee_id"
    t.datetime "updated_at", null: false
    t.index ["escalation_rule_id"], name: "index_escalation_levels_on_escalation_rule_id"
    t.index ["notify_user_id"], name: "index_escalation_levels_on_notify_user_id"
    t.index ["tenant_id", "escalation_rule_id", "position"], name: "idx_on_tenant_id_escalation_rule_id_position_b715169712"
    t.index ["tenant_id"], name: "index_escalation_levels_on_tenant_id"
    t.index ["then_assignee_id"], name: "index_escalation_levels_on_then_assignee_id"
  end

  create_table "escalation_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "breach_clock", default: "resolution", null: false
    t.datetime "created_at", null: false
    t.string "if_priority"
    t.string "if_status"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "tenant_id", null: false
    t.integer "trigger_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "position"], name: "index_escalation_rules_on_tenant_id_and_position"
    t.index ["tenant_id"], name: "index_escalation_rules_on_tenant_id"
  end

  create_table "import_conflicts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "current_value"
    t.string "external_id", null: false
    t.string "field", null: false
    t.bigint "import_identity_id"
    t.bigint "import_run_id", null: false
    t.json "incoming_value"
    t.json "previous_imported_value"
    t.string "source_type", null: false
    t.string "status", default: "unresolved", null: false
    t.bigint "target_id"
    t.string "target_type"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["import_identity_id"], name: "index_import_conflicts_on_import_identity_id"
    t.index ["import_run_id"], name: "index_import_conflicts_on_import_run_id"
    t.index ["target_type", "target_id"], name: "index_import_conflicts_on_target"
    t.index ["tenant_id", "status"], name: "index_import_conflicts_on_tenant_id_and_status"
    t.index ["tenant_id"], name: "index_import_conflicts_on_tenant_id"
  end

  create_table "import_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.json "imported_attributes"
    t.bigint "last_seen_run_id"
    t.json "metadata"
    t.string "source", null: false
    t.string "source_digest", limit: 64
    t.string "source_instance", default: "default", null: false
    t.string "source_type", null: false
    t.datetime "source_updated_at"
    t.bigint "target_id"
    t.string "target_type"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["last_seen_run_id"], name: "index_import_identities_on_last_seen_run_id"
    t.index ["target_type", "target_id"], name: "index_import_identities_on_target"
    t.index ["tenant_id", "source", "source_instance", "source_type", "external_id"], name: "index_import_identities_on_source_identity", unique: true
    t.index ["tenant_id"], name: "index_import_identities_on_tenant_id"
  end

  create_table "import_runs", force: :cascade do |t|
    t.json "checkpoint"
    t.datetime "completed_at"
    t.json "conflicts"
    t.datetime "created_at", null: false
    t.boolean "dry_run", default: true, null: false
    t.json "error_messages"
    t.json "options"
    t.datetime "previous_watermark"
    t.string "resume_token", null: false
    t.string "source", null: false
    t.string "source_instance", default: "default", null: false
    t.datetime "started_at", null: false
    t.json "stats"
    t.string "status", default: "running", null: false
    t.bigint "tenant_id", null: false
    t.json "unmapped"
    t.datetime "updated_at", null: false
    t.datetime "watermark"
    t.index ["resume_token"], name: "index_import_runs_on_resume_token", unique: true
    t.index ["tenant_id", "source", "source_instance", "status"], name: "index_import_runs_for_resume"
    t.index ["tenant_id"], name: "index_import_runs_on_tenant_id"
  end

  create_table "knowledge_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.integer "parent_id"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_knowledge_categories_on_deleted_at"
    t.index ["parent_id"], name: "index_knowledge_categories_on_parent_id"
    t.index ["tenant_id", "name"], name: "index_knowledge_categories_on_root_name", unique: true, where: "parent_id IS NULL AND deleted_at IS NULL"
    t.index ["tenant_id", "parent_id", "name"], name: "index_knowledge_categories_on_parent_and_name", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id", "slug"], name: "index_knowledge_categories_on_tenant_id_and_slug", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_knowledge_categories_on_tenant_id"
  end

  create_table "lead_capture_forms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "campaign_id"
    t.text "consent_disclosure"
    t.datetime "created_at", null: false
    t.json "field_mapping", default: {}, null: false
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_lead_capture_forms_on_campaign_id"
    t.index ["tenant_id", "slug"], name: "index_lead_capture_forms_on_tenant_id_and_slug", unique: true
    t.index ["tenant_id"], name: "index_lead_capture_forms_on_tenant_id"
    t.index ["tenant_id"], name: "index_lead_capture_forms_one_default", unique: true, where: "is_default"
  end

  create_table "lead_routing_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "if_company_contains"
    t.string "if_email_domain"
    t.string "if_source"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "tenant_id", null: false
    t.integer "then_assignment", default: 0, null: false
    t.integer "then_owner_id"
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "position"], name: "index_lead_routing_rules_on_tenant_id_and_position"
    t.index ["tenant_id"], name: "index_lead_routing_rules_on_tenant_id"
    t.index ["then_owner_id"], name: "index_lead_routing_rules_on_then_owner_id"
  end

  create_table "lead_scorecards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "hot_threshold", default: 5, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "warm_sources", default: "referral,web_form", null: false
    t.integer "warm_threshold", default: 3, null: false
    t.integer "weight_company", default: 1, null: false
    t.integer "weight_email", default: 1, null: false
    t.integer "weight_owned", default: 1, null: false
    t.integer "weight_phone", default: 1, null: false
    t.integer "weight_warm_source", default: 1, null: false
    t.index ["tenant_id"], name: "index_lead_scorecards_on_tenant_id", unique: true
  end

  create_table "leads", force: :cascade do |t|
    t.string "company_name"
    t.datetime "consent_captured_at"
    t.string "consent_source"
    t.integer "contact_id"
    t.datetime "converted_at"
    t.integer "converted_deal_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.boolean "email_consent", default: false, null: false
    t.datetime "email_unsubscribed_at"
    t.string "external_id"
    t.datetime "first_touch_at"
    t.integer "first_touch_campaign_id"
    t.text "first_touch_landing_page"
    t.text "first_touch_referrer"
    t.string "first_touch_utm_campaign"
    t.string "first_touch_utm_content"
    t.string "first_touch_utm_medium"
    t.string "first_touch_utm_source"
    t.string "first_touch_utm_term"
    t.json "labels"
    t.datetime "merged_at"
    t.bigint "merged_into_id"
    t.string "name", null: false
    t.text "notes"
    t.integer "owner_id"
    t.string "phone"
    t.json "provenance", default: {}, null: false
    t.integer "score", default: 0, null: false
    t.integer "score_band", default: 0, null: false
    t.boolean "sms_consent", default: false, null: false
    t.integer "source", default: 2, null: false
    t.integer "source_connector_id"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "value_estimate_cents"
    t.index ["contact_id"], name: "index_leads_on_contact_id"
    t.index ["converted_deal_id"], name: "index_leads_on_converted_deal_id"
    t.index ["deleted_at"], name: "index_leads_on_deleted_at"
    t.index ["email"], name: "index_leads_on_email"
    t.index ["external_id"], name: "index_leads_on_external_id"
    t.index ["first_touch_campaign_id"], name: "index_leads_on_first_touch_campaign_id"
    t.index ["merged_into_id"], name: "index_leads_on_merged_into_id"
    t.index ["owner_id"], name: "index_leads_on_owner_id"
    t.index ["source_connector_id"], name: "index_leads_on_source_connector_id"
    t.index ["status"], name: "index_leads_on_status"
    t.index ["tenant_id", "merged_into_id"], name: "index_leads_on_tenant_id_and_merged_into_id"
    t.index ["tenant_id", "score_band"], name: "index_leads_on_tenant_id_and_score_band"
    t.index ["tenant_id"], name: "index_leads_on_tenant_id"
  end

  create_table "legal_holds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "placed_by_id"
    t.text "reason", null: false
    t.datetime "released_at"
    t.bigint "released_by_id"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["placed_by_id"], name: "index_legal_holds_on_placed_by_id"
    t.index ["released_by_id"], name: "index_legal_holds_on_released_by_id"
    t.index ["subject_type", "subject_id"], name: "index_legal_holds_on_subject"
    t.index ["tenant_id", "subject_type", "subject_id", "released_at"], name: "index_legal_holds_on_active_subject"
    t.index ["tenant_id"], name: "index_legal_holds_on_tenant_id"
  end

  create_table "macros", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "message_kind"
    t.string "name", null: false
    t.bigint "set_assignee_id"
    t.string "set_priority"
    t.bigint "set_queue_id"
    t.string "set_status"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_macros_on_deleted_at"
    t.index ["set_assignee_id"], name: "index_macros_on_set_assignee_id"
    t.index ["set_queue_id"], name: "index_macros_on_set_queue_id"
    t.index ["tenant_id", "name"], name: "index_macros_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_macros_on_tenant_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "author_id"
    t.string "author_type"
    t.text "body", null: false
    t.integer "case_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "direction", default: 0, null: false
    t.string "email_message_id"
    t.string "external_message_id"
    t.integer "kind", default: 0, null: false
    t.json "metadata"
    t.string "source_author_name"
    t.integer "source_connector_id"
    t.string "subject"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_messages_on_author"
    t.index ["case_id", "created_at"], name: "index_messages_on_case_id_and_created_at"
    t.index ["case_id"], name: "index_messages_on_case_id"
    t.index ["deleted_at"], name: "index_messages_on_deleted_at"
    t.index ["email_message_id"], name: "index_messages_on_email_message_id"
    t.index ["source_connector_id"], name: "index_messages_on_source_connector_id"
    t.index ["tenant_id", "source_connector_id", "external_message_id"], name: "index_messages_on_tenant_connector_external_id", unique: true, where: "((source_connector_id IS NOT NULL) AND (external_message_id IS NOT NULL))"
    t.index ["tenant_id"], name: "index_messages_on_tenant_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "dedupe_key", null: false
    t.integer "email_attempts", default: 0, null: false
    t.datetime "email_claimed_at"
    t.integer "email_delivery_count", default: 0, null: false
    t.text "email_last_error"
    t.integer "email_status", default: 0, null: false
    t.datetime "emailed_at"
    t.integer "kind", null: false
    t.datetime "last_occurred_at", null: false
    t.json "metadata"
    t.bigint "notifiable_id", null: false
    t.string "notifiable_type", null: false
    t.integer "occurrences", default: 1, null: false
    t.datetime "read_at"
    t.integer "severity", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_type", "actor_id"], name: "index_notifications_on_actor"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["tenant_id", "email_status"], name: "index_notifications_on_tenant_id_and_email_status"
    t.index ["tenant_id", "user_id", "dedupe_key"], name: "index_notifications_on_recipient_and_dedupe", unique: true
    t.index ["tenant_id"], name: "index_notifications_on_tenant_id"
    t.index ["user_id", "read_at", "created_at"], name: "index_notifications_on_user_inbox"
    t.index ["user_id"], name: "index_notifications_on_user_id"
    t.check_constraint "email_delivery_count >= 0", name: "notifications_email_delivery_count_nonnegative"
    t.check_constraint "occurrences > 0", name: "notifications_occurrences_positive"
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.json "scopes", null: false
    t.integer "service_account_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_oauth_access_tokens_on_expires_at"
    t.index ["service_account_id"], name: "index_oauth_access_tokens_on_service_account_id"
    t.index ["token_digest"], name: "index_oauth_access_tokens_on_token_digest", unique: true
  end

  create_table "organisations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "external_ref"
    t.string "kind", default: "department", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "parent_id"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_organisations_on_deleted_at"
    t.index ["external_ref"], name: "index_organisations_on_external_ref"
    t.index ["parent_id"], name: "index_organisations_on_parent_id"
    t.index ["tenant_id", "name"], name: "index_organisations_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_organisations_on_tenant_id"
  end

  create_table "pipeline_stages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "is_lost", default: false, null: false
    t.boolean "is_won", default: false, null: false
    t.string "name", null: false
    t.integer "pipeline_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "probability"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_pipeline_stages_on_deleted_at"
    t.index ["pipeline_id", "position"], name: "index_pipeline_stages_on_pipeline_id_and_position"
    t.index ["pipeline_id"], name: "index_pipeline_stages_on_pipeline_id"
  end

  create_table "pipelines", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_pipelines_on_deleted_at"
    t.index ["tenant_id", "slug"], name: "index_pipelines_on_tenant_id_and_slug", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_pipelines_on_tenant_id"
  end

  create_table "price_book_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.integer "price_book_id", null: false
    t.integer "product_id", null: false
    t.integer "tenant_id", null: false
    t.bigint "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["price_book_id", "product_id", "currency"], name: "index_price_book_entries_uniqueness", unique: true
    t.index ["price_book_id"], name: "index_price_book_entries_on_price_book_id"
    t.index ["product_id"], name: "index_price_book_entries_on_product_id"
    t.index ["tenant_id"], name: "index_price_book_entries_on_tenant_id"
  end

  create_table "price_books", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "is_default", default: false, null: false
    t.string "name", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_price_books_on_tenant_id_and_name", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_price_books_on_tenant_id"
    t.index ["tenant_id"], name: "index_price_books_one_default", unique: true, where: "is_default AND deleted_at IS NULL"
  end

  create_table "privacy_erasure_requests", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "erasure_token", null: false
    t.text "failure_reason"
    t.bigint "requested_by_id"
    t.integer "status", default: 0, null: false
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.json "summary", default: {}, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["erasure_token"], name: "index_privacy_erasure_requests_on_erasure_token", unique: true
    t.index ["requested_by_id"], name: "index_privacy_erasure_requests_on_requested_by_id"
    t.index ["subject_type", "subject_id"], name: "index_privacy_erasure_requests_on_subject"
    t.index ["tenant_id"], name: "index_privacy_erasure_requests_on_tenant_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.bigint "default_unit_price_cents"
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.string "sku", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "sku"], name: "index_products_on_tenant_id_and_sku", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_products_on_tenant_id"
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["tenant_id"], name: "index_project_memberships_on_tenant_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "project_template_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "due_offset_days"
    t.decimal "estimate", precision: 8, scale: 2
    t.integer "kind", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.bigint "project_template_id", null: false
    t.bigint "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_template_id"], name: "index_project_template_items_on_project_template_id"
    t.index ["tenant_id", "project_template_id", "position"], name: "index_project_template_items_order"
    t.index ["tenant_id"], name: "index_project_template_items_on_tenant_id"
  end

  create_table "project_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key_prefix", default: "ONB", null: false
    t.string "name", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_project_templates_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_project_templates_on_tenant_id"
  end

  create_table "projects", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "key", null: false
    t.integer "kind", default: 0, null: false
    t.integer "last_item_number", default: 0, null: false
    t.integer "lead_id"
    t.string "name", null: false
    t.bigint "onboarding_deal_id"
    t.bigint "project_template_id"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["deleted_at"], name: "index_projects_on_deleted_at"
    t.index ["lead_id"], name: "index_projects_on_lead_id"
    t.index ["onboarding_deal_id"], name: "index_projects_on_onboarding_deal_id"
    t.index ["project_template_id"], name: "index_projects_on_project_template_id"
    t.index ["tenant_id", "key"], name: "index_projects_on_tenant_id_and_key", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id", "onboarding_deal_id"], name: "index_projects_on_tenant_onboarding_deal", unique: true, where: "(onboarding_deal_id IS NOT NULL)"
    t.index ["tenant_id", "visibility"], name: "index_projects_on_tenant_id_and_visibility"
    t.index ["tenant_id"], name: "index_projects_on_tenant_id"
    t.check_constraint "visibility IN (0, 1)", name: "projects_visibility_valid"
  end

  create_table "queue_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "queue_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["queue_id", "user_id"], name: "index_queue_memberships_on_queue_id_and_user_id", unique: true
    t.index ["queue_id"], name: "index_queue_memberships_on_queue_id"
    t.index ["user_id"], name: "index_queue_memberships_on_user_id"
  end

  create_table "queues", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_queues_on_deleted_at"
    t.index ["tenant_id", "name"], name: "index_queues_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id", "slug"], name: "index_queues_on_tenant_id_and_slug", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_queues_on_tenant_id"
  end

  create_table "quote_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "description", null: false
    t.string "hsn_sac"
    t.integer "position", default: 0, null: false
    t.decimal "quantity", precision: 12, scale: 3, default: "1.0", null: false
    t.integer "quote_id", null: false
    t.decimal "tax_rate", precision: 6, scale: 3, default: "0.0", null: false
    t.integer "tenant_id", null: false
    t.bigint "unit_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["quote_id"], name: "index_quote_line_items_on_quote_id"
    t.index ["tenant_id", "quote_id"], name: "index_quote_line_items_on_tenant_id_and_quote_id"
    t.index ["tenant_id"], name: "index_quote_line_items_on_tenant_id"
  end

  create_table "quote_milestones", force: :cascade do |t|
    t.bigint "amount_cents"
    t.datetime "created_at", null: false
    t.date "due_on"
    t.string "name", null: false
    t.decimal "percentage", precision: 6, scale: 3
    t.integer "position", default: 0, null: false
    t.integer "quote_id", null: false
    t.integer "tenant_id", null: false
    t.string "trigger"
    t.datetime "updated_at", null: false
    t.index ["quote_id"], name: "index_quote_milestones_on_quote_id"
    t.index ["tenant_id", "quote_id"], name: "index_quote_milestones_on_tenant_id_and_quote_id"
    t.index ["tenant_id"], name: "index_quote_milestones_on_tenant_id"
  end

  create_table "quotes", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "billing_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.integer "deal_id", null: false
    t.datetime "deleted_at"
    t.integer "deliverable_id"
    t.text "notes"
    t.integer "number", null: false
    t.datetime "rejected_at"
    t.text "rejection_reason"
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.integer "supersedes_id"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.date "valid_until"
    t.integer "version", default: 1, null: false
    t.index ["deal_id"], name: "index_quotes_on_deal_id"
    t.index ["deliverable_id"], name: "index_quotes_on_deliverable_id"
    t.index ["supersedes_id"], name: "index_quotes_on_supersedes_id"
    t.index ["tenant_id", "deal_id"], name: "index_quotes_on_tenant_id_and_deal_id"
    t.index ["tenant_id", "number", "version"], name: "index_quotes_on_tenant_id_and_number_and_version", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_quotes_on_tenant_id"
  end

  create_table "reference_doc_ratings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "helpful", null: false
    t.integer "reference_doc_id", null: false
    t.integer "reference_doc_version_id", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "visitor_token_digest", null: false
    t.index ["reference_doc_id"], name: "index_reference_doc_ratings_on_reference_doc_id"
    t.index ["reference_doc_version_id", "visitor_token_digest"], name: "index_reference_doc_ratings_on_version_and_visitor", unique: true
    t.index ["reference_doc_version_id"], name: "index_reference_doc_ratings_on_reference_doc_version_id"
    t.index ["tenant_id"], name: "index_reference_doc_ratings_on_tenant_id"
  end

  create_table "reference_doc_versions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "knowledge_category_id"
    t.string "locale", null: false
    t.integer "number", null: false
    t.integer "reference_doc_id", null: false
    t.integer "status", null: false
    t.integer "tenant_id", null: false
    t.string "title", null: false
    t.integer "visibility", null: false
    t.index ["created_by_id"], name: "index_reference_doc_versions_on_created_by_id"
    t.index ["knowledge_category_id"], name: "index_reference_doc_versions_on_knowledge_category_id"
    t.index ["reference_doc_id", "number"], name: "index_reference_doc_versions_on_doc_and_number", unique: true
    t.index ["reference_doc_id"], name: "index_reference_doc_versions_on_reference_doc_id"
    t.index ["tenant_id"], name: "index_reference_doc_versions_on_tenant_id"
  end

  create_table "reference_docs", force: :cascade do |t|
    t.text "body", null: false
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.integer "current_version_id"
    t.datetime "deleted_at"
    t.integer "knowledge_category_id"
    t.string "locale", default: "en", null: false
    t.string "slug"
    t.integer "status", default: 1, null: false
    t.integer "tenant_id", null: false
    t.string "title", null: false
    t.string "translation_key", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["category_id"], name: "index_reference_docs_on_category_id"
    t.index ["current_version_id"], name: "index_reference_docs_on_current_version_id"
    t.index ["deleted_at"], name: "index_reference_docs_on_deleted_at"
    t.index ["knowledge_category_id"], name: "index_reference_docs_on_knowledge_category_id"
    t.index ["tenant_id", "locale", "title"], name: "index_reference_docs_on_tenant_locale_title", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id", "slug"], name: "index_reference_docs_on_tenant_id_and_slug", unique: true, where: "((slug IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["tenant_id", "translation_key", "locale"], name: "index_reference_docs_on_translation_and_locale", unique: true, where: "deleted_at IS NULL"
    t.index ["tenant_id"], name: "index_reference_docs_on_tenant_id"
  end

  create_table "routing_rule_executions", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.datetime "case_status_changed_at", null: false
    t.text "changes_summary"
    t.datetime "created_at", null: false
    t.datetime "executed_at", null: false
    t.bigint "routing_rule_id"
    t.string "rule_name", null: false
    t.datetime "scheduled_for", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id"], name: "index_routing_rule_executions_on_case_id"
    t.index ["routing_rule_id", "case_id", "case_status_changed_at"], name: "index_routing_executions_on_rule_case_episode", unique: true
    t.index ["routing_rule_id"], name: "index_routing_rule_executions_on_routing_rule_id"
    t.index ["tenant_id"], name: "index_routing_rule_executions_on_tenant_id"
  end

  create_table "routing_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "after_minutes"
    t.datetime "created_at", null: false
    t.string "if_channel"
    t.string "if_priority"
    t.string "if_status"
    t.string "if_subject_contains"
    t.integer "match_category_id"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "tenant_id", null: false
    t.integer "then_assignee_id"
    t.integer "then_assignment", default: 0, null: false
    t.integer "then_category_id"
    t.string "then_priority"
    t.integer "then_queue_id"
    t.string "trigger_type", default: "case_created", null: false
    t.datetime "updated_at", null: false
    t.boolean "use_business_hours", default: true, null: false
    t.index ["match_category_id"], name: "index_routing_rules_on_match_category_id"
    t.index ["tenant_id", "position"], name: "index_routing_rules_on_tenant_id_and_position"
    t.index ["tenant_id"], name: "index_routing_rules_on_tenant_id"
    t.index ["then_assignee_id"], name: "index_routing_rules_on_then_assignee_id"
    t.index ["then_category_id"], name: "index_routing_rules_on_then_category_id"
    t.index ["then_queue_id"], name: "index_routing_rules_on_then_queue_id"
  end

  create_table "saved_views", force: :cascade do |t|
    t.integer "context_id"
    t.datetime "created_at", null: false
    t.json "filters", default: {}, null: false
    t.string "name", null: false
    t.string "resource_type", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id", "user_id", "resource_type", "context_id", "name"], name: "index_saved_work_views_on_owner_context_and_name", unique: true, where: "(context_id IS NOT NULL)"
    t.index ["tenant_id", "user_id", "resource_type", "name"], name: "index_saved_case_views_on_owner_and_name", unique: true, where: "(context_id IS NULL)"
    t.index ["tenant_id"], name: "index_saved_views_on_tenant_id"
    t.index ["user_id"], name: "index_saved_views_on_user_id"
  end

  create_table "security_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "ip_address"
    t.string "kind", null: false
    t.json "metadata"
    t.integer "tenant_id"
    t.string "user_agent"
    t.index ["created_at"], name: "index_security_events_on_created_at"
    t.index ["kind"], name: "index_security_events_on_kind"
    t.index ["tenant_id"], name: "index_security_events_on_tenant_id"
  end

  create_table "sequence_deliveries", force: :cascade do |t|
    t.integer "activity_id"
    t.string "channel", null: false
    t.datetime "claimed_at"
    t.integer "click_count", default: 0, null: false
    t.datetime "clicked_at"
    t.integer "connector_id"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "last_error"
    t.integer "open_count", default: 0, null: false
    t.datetime "opened_at"
    t.json "payload", default: {}, null: false
    t.string "recipient"
    t.datetime "replied_at"
    t.integer "sequence_enrollment_id", null: false
    t.integer "sequence_step_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.string "tracking_token"
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_sequence_deliveries_on_activity_id"
    t.index ["connector_id"], name: "index_sequence_deliveries_on_connector_id"
    t.index ["sequence_enrollment_id", "sequence_step_id"], name: "index_sequence_deliveries_on_enrollment_and_step", unique: true
    t.index ["sequence_enrollment_id"], name: "index_sequence_deliveries_on_sequence_enrollment_id"
    t.index ["sequence_step_id"], name: "index_sequence_deliveries_on_sequence_step_id"
    t.index ["status", "created_at"], name: "index_sequence_deliveries_on_status_and_created_at"
    t.index ["tenant_id"], name: "index_sequence_deliveries_on_tenant_id"
    t.index ["tracking_token"], name: "index_sequence_deliveries_on_tracking_token", unique: true
  end

  create_table "sequence_enrollments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_step_id"
    t.integer "current_step_position", default: 0, null: false
    t.datetime "deleted_at"
    t.integer "enrollable_id", null: false
    t.string "enrollable_type", null: false
    t.datetime "next_run_at"
    t.integer "sequence_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["current_step_id"], name: "index_sequence_enrollments_on_current_step_id"
    t.index ["deleted_at"], name: "index_sequence_enrollments_on_deleted_at"
    t.index ["enrollable_type", "enrollable_id"], name: "index_sequence_enrollments_on_enrollable"
    t.index ["sequence_id"], name: "index_sequence_enrollments_on_sequence_id"
    t.index ["status", "next_run_at"], name: "index_sequence_enrollments_on_status_and_next_run_at"
    t.index ["tenant_id", "sequence_id", "enrollable_type", "enrollable_id"], name: "index_sequence_enrollments_on_unique_active_target", unique: true, where: "((status = 0) AND (deleted_at IS NULL))"
    t.index ["tenant_id"], name: "index_sequence_enrollments_on_tenant_id"
  end

  create_table "sequence_steps", force: :cascade do |t|
    t.text "body"
    t.integer "channel", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "delay_days", default: 0, null: false
    t.integer "delay_hours", default: 0, null: false
    t.datetime "deleted_at"
    t.integer "position", default: 0, null: false
    t.integer "sequence_id", null: false
    t.string "subject"
    t.string "template_key"
    t.datetime "updated_at", null: false
    t.boolean "use_business_hours", default: false, null: false
    t.index ["deleted_at"], name: "index_sequence_steps_on_deleted_at"
    t.index ["sequence_id", "position"], name: "index_sequence_steps_on_sequence_id_and_position"
    t.index ["sequence_id"], name: "index_sequence_steps_on_sequence_id"
  end

  create_table "sequences", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "business_calendar_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.integer "owner_id"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["business_calendar_id"], name: "index_sequences_on_business_calendar_id"
    t.index ["deleted_at"], name: "index_sequences_on_deleted_at"
    t.index ["owner_id"], name: "index_sequences_on_owner_id"
    t.index ["tenant_id"], name: "index_sequences_on_tenant_id"
  end

  create_table "service_account_connector_grants", force: :cascade do |t|
    t.json "actions", default: [], null: false
    t.integer "connector_id", null: false
    t.datetime "created_at", null: false
    t.integer "service_account_id", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["connector_id"], name: "index_service_account_connector_grants_on_connector_id"
    t.index ["service_account_id"], name: "index_service_account_connector_grants_on_service_account_id"
    t.index ["tenant_id", "service_account_id", "connector_id"], name: "index_service_account_connector_grants_uniqueness", unique: true
    t.index ["tenant_id"], name: "index_service_account_connector_grants_on_tenant_id"
  end

  create_table "service_accounts", force: :cascade do |t|
    t.integer "action_budget"
    t.integer "action_budget_window_minutes"
    t.boolean "active", default: true, null: false
    t.string "client_id", null: false
    t.string "client_secret_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.json "scopes", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_service_accounts_on_client_id", unique: true
    t.index ["deleted_at"], name: "index_service_accounts_on_deleted_at"
    t.index ["tenant_id"], name: "index_service_accounts_on_tenant_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "tenant_id"
    t.datetime "updated_at", null: false
    t.json "value"
    t.index ["key"], name: "index_settings_on_key_global", unique: true, where: "(tenant_id IS NULL)"
    t.index ["tenant_id", "key"], name: "index_settings_on_tenant_id_and_key", unique: true, where: "(tenant_id IS NOT NULL)"
    t.index ["tenant_id"], name: "index_settings_on_tenant_id"
  end

  create_table "shared_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "label", null: false
    t.string "name", null: false
    t.text "secrets"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_shared_credentials_on_deleted_at"
    t.index ["tenant_id", "name"], name: "index_shared_credentials_on_tenant_id_and_name_live", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_shared_credentials_on_tenant_id"
  end

  create_table "sla_clock_events", force: :cascade do |t|
    t.bigint "case_id", null: false
    t.integer "clock_kind", null: false
    t.datetime "created_at", null: false
    t.integer "event_kind", null: false
    t.json "metadata"
    t.datetime "occurred_at", null: false
    t.string "reason"
    t.integer "remaining_minutes"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["case_id", "clock_kind", "occurred_at"], name: "index_sla_clock_events_timeline"
    t.index ["case_id"], name: "index_sla_clock_events_on_case_id"
    t.index ["tenant_id"], name: "index_sla_clock_events_on_tenant_id"
    t.check_constraint "remaining_minutes >= 0", name: "sla_clock_events_remaining_nonnegative"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.bigint "business_calendar_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["business_calendar_id"], name: "index_sla_policies_on_business_calendar_id"
    t.index ["deleted_at"], name: "index_sla_policies_on_deleted_at"
    t.index ["tenant_id", "name"], name: "index_sla_policies_on_tenant_id_and_name", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_sla_policies_on_tenant_id"
  end

  create_table "sla_targets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "first_response_minutes", null: false
    t.integer "priority", null: false
    t.integer "resolution_minutes", null: false
    t.integer "sla_policy_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sla_policy_id", "priority"], name: "index_sla_targets_on_sla_policy_id_and_priority", unique: true
    t.index ["sla_policy_id"], name: "index_sla_targets_on_sla_policy_id"
  end

  create_table "sprints", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.date "ends_on"
    t.text "goal"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.json "rolled_out_item_ids", default: [], null: false
    t.date "starts_on"
    t.integer "status", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sprints_on_deleted_at"
    t.index ["project_id"], name: "index_sprints_on_one_active_per_project", unique: true, where: "status = 1 AND deleted_at IS NULL"
    t.index ["project_id"], name: "index_sprints_on_project_id"
    t.index ["tenant_id"], name: "index_sprints_on_tenant_id"
  end

  create_table "storage_deletions", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "blob_key", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "last_error"
    t.bigint "owner_tenant_id", null: false
    t.string "service_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["blob_key"], name: "index_storage_deletions_on_blob_key", unique: true
    t.index ["owner_tenant_id"], name: "index_storage_deletions_on_owner_tenant_id"
    t.index ["status", "created_at"], name: "index_storage_deletions_on_status_and_created_at"
  end

  create_table "tenant_export_receipts", force: :cascade do |t|
    t.integer "attachment_count", default: 0, null: false
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.string "export_id", null: false
    t.string "export_path", null: false
    t.string "inventory_sha256", null: false
    t.string "manifest_sha256", null: false
    t.json "row_counts", default: {}, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["export_id"], name: "index_tenant_export_receipts_on_export_id", unique: true
    t.index ["tenant_id"], name: "index_tenant_export_receipts_on_tenant_id"
    t.check_constraint "attachment_count >= 0", name: "tenant_export_receipts_attachment_count_nonnegative"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "entitlements", default: {}, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email_address", null: false
    t.text "email_signature"
    t.string "locale"
    t.string "name", default: "", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 2, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["role"], name: "index_users_on_role"
    t.index ["tenant_id", "email_address"], name: "index_users_on_tenant_id_and_email_address", unique: true, where: "(deleted_at IS NULL)"
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "event", null: false
    t.string "last_error"
    t.json "payload", null: false
    t.integer "response_code"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_endpoint_id", null: false
    t.index ["status"], name: "index_webhook_deliveries_on_status"
    t.index ["webhook_endpoint_id", "created_at"], name: "index_webhook_deliveries_on_webhook_endpoint_id_and_created_at"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.json "events", null: false
    t.string "name", null: false
    t.string "secret", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["deleted_at"], name: "index_webhook_endpoints_on_deleted_at"
    t.index ["tenant_id"], name: "index_webhook_endpoints_on_tenant_id"
  end

  create_table "work_assignment_rules", force: :cascade do |t|
    t.bigint "assignee_id", null: false
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "work_kind", null: false
    t.index ["assignee_id"], name: "index_work_assignment_rules_on_assignee_id"
    t.index ["project_id"], name: "index_work_assignment_rules_on_project_id"
    t.index ["tenant_id", "project_id", "work_kind"], name: "index_work_assignment_rules_on_project_and_kind", unique: true
    t.index ["tenant_id"], name: "index_work_assignment_rules_on_tenant_id"
  end

  create_table "work_comments", force: :cascade do |t|
    t.integer "author_id"
    t.string "author_type"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "source_author_name"
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "work_item_id", null: false
    t.index ["author_type", "author_id"], name: "index_work_comments_on_author_type_and_author_id"
    t.index ["deleted_at"], name: "index_work_comments_on_deleted_at"
    t.index ["tenant_id"], name: "index_work_comments_on_tenant_id"
    t.index ["work_item_id"], name: "index_work_comments_on_work_item_id"
  end

  create_table "work_item_relations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "relation_type", null: false
    t.bigint "source_id", null: false
    t.bigint "target_id", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_work_item_relations_on_created_by_id"
    t.index ["source_id"], name: "index_work_item_relations_on_source_id"
    t.index ["target_id"], name: "index_work_item_relations_on_target_id"
    t.index ["tenant_id", "source_id", "target_id", "relation_type"], name: "index_work_relations_on_tenant_pair_and_type", unique: true
    t.index ["tenant_id"], name: "index_work_item_relations_on_tenant_id"
    t.check_constraint "source_id <> target_id", name: "work_item_relations_distinct_items"
  end

  create_table "work_items", force: :cascade do |t|
    t.integer "assignee_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.json "custom_fields", default: {}, null: false
    t.datetime "deleted_at"
    t.text "description"
    t.date "due_on"
    t.decimal "estimate", precision: 6, scale: 2
    t.integer "kind", default: 0, null: false
    t.json "labels"
    t.integer "number", null: false
    t.integer "parent_id"
    t.integer "position", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.integer "project_id", null: false
    t.integer "reporter_id"
    t.string "source_key"
    t.integer "sprint_id"
    t.integer "tenant_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_state_id", null: false
    t.index ["assignee_id"], name: "index_work_items_on_assignee_id"
    t.index ["deleted_at"], name: "index_work_items_on_deleted_at"
    t.index ["parent_id"], name: "index_work_items_on_parent_id"
    t.index ["project_id", "number"], name: "index_work_items_on_project_id_and_number", unique: true
    t.index ["project_id", "source_key"], name: "index_work_items_on_project_id_and_source_key", unique: true, where: "((source_key IS NOT NULL) AND (deleted_at IS NULL))"
    t.index ["project_id"], name: "index_work_items_on_project_id"
    t.index ["reporter_id"], name: "index_work_items_on_reporter_id"
    t.index ["sprint_id"], name: "index_work_items_on_sprint_id"
    t.index ["tenant_id"], name: "index_work_items_on_tenant_id"
    t.index ["workflow_state_id"], name: "index_work_items_on_workflow_state_id"
  end

  create_table "work_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.integer "linkable_id", null: false
    t.string "linkable_type", null: false
    t.integer "relation", default: 0, null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "work_item_id", null: false
    t.index ["created_by_id"], name: "index_work_links_on_created_by_id"
    t.index ["linkable_type", "linkable_id"], name: "index_work_links_on_linkable"
    t.index ["linkable_type", "linkable_id"], name: "index_work_links_on_linkable_type_and_linkable_id"
    t.index ["tenant_id"], name: "index_work_links_on_tenant_id"
    t.index ["work_item_id", "linkable_type", "linkable_id"], name: "index_work_links_uniqueness", unique: true
    t.index ["work_item_id"], name: "index_work_links_on_work_item_id"
  end

  create_table "work_watches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "work_item_id", null: false
    t.index ["tenant_id"], name: "index_work_watches_on_tenant_id"
    t.index ["user_id"], name: "index_work_watches_on_user_id"
    t.index ["work_item_id", "user_id"], name: "index_work_watches_on_work_item_id_and_user_id", unique: true
    t.index ["work_item_id"], name: "index_work_watches_on_work_item_id"
  end

  create_table "workflow_states", force: :cascade do |t|
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "project_id", null: false
    t.integer "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "wip_limit"
    t.index ["deleted_at"], name: "index_workflow_states_on_deleted_at"
    t.index ["project_id", "position"], name: "index_workflow_states_on_project_id_and_position"
    t.index ["project_id"], name: "index_workflow_states_on_project_id"
    t.index ["tenant_id"], name: "index_workflow_states_on_tenant_id"
  end

  add_foreign_key "action_mailbox_inbound_emails", "tenants"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "tenants", on_delete: :cascade
  add_foreign_key "activities", "users", column: "owner_id", on_delete: :nullify
  add_foreign_key "api_tokens", "users"
  add_foreign_key "approval_processes", "tenants"
  add_foreign_key "approval_requests", "approval_processes"
  add_foreign_key "approval_requests", "tenants"
  add_foreign_key "approval_requests", "users", column: "decided_by_id"
  add_foreign_key "approval_requests", "users", column: "requested_by_id"
  add_foreign_key "business_calendar_exceptions", "business_calendars"
  add_foreign_key "business_calendar_windows", "business_calendars"
  add_foreign_key "business_calendars", "tenants"
  add_foreign_key "campaigns", "tenants"
  add_foreign_key "case_presences", "cases", on_delete: :cascade
  add_foreign_key "case_presences", "tenants", on_delete: :cascade
  add_foreign_key "case_presences", "users", on_delete: :cascade
  add_foreign_key "cases", "cases", column: "merged_into_id", on_delete: :restrict
  add_foreign_key "cases", "categories"
  add_foreign_key "cases", "contacts"
  add_foreign_key "cases", "queues"
  add_foreign_key "cases", "routing_rules", column: "routed_by_rule_id"
  add_foreign_key "cases", "sla_policies"
  add_foreign_key "cases", "tenants"
  add_foreign_key "cases", "users", column: "assignee_id"
  add_foreign_key "categories", "tenants"
  add_foreign_key "competitors", "tenants", on_delete: :cascade
  add_foreign_key "connector_invocations", "connectors"
  add_foreign_key "connector_invocations", "tenants"
  add_foreign_key "connector_invocations", "users", column: "approved_by_id"
  add_foreign_key "connector_runs", "connectors"
  add_foreign_key "connector_runs", "tenants"
  add_foreign_key "connectors", "shared_credentials"
  add_foreign_key "connectors", "tenants"
  add_foreign_key "contacts", "organisations"
  add_foreign_key "contacts", "tenants"
  add_foreign_key "csat_surveys", "cases", on_delete: :cascade
  add_foreign_key "csat_surveys", "contacts", on_delete: :nullify
  add_foreign_key "csat_surveys", "tenants", on_delete: :cascade
  add_foreign_key "custom_field_definitions", "tenants", on_delete: :cascade
  add_foreign_key "deal_competitors", "competitors", on_delete: :restrict
  add_foreign_key "deal_competitors", "deals", on_delete: :cascade
  add_foreign_key "deal_competitors", "tenants", on_delete: :cascade
  add_foreign_key "deal_contact_roles", "contacts", on_delete: :cascade
  add_foreign_key "deal_contact_roles", "deals", on_delete: :cascade
  add_foreign_key "deal_contact_roles", "tenants", on_delete: :cascade
  add_foreign_key "deal_line_items", "deals", on_delete: :cascade
  add_foreign_key "deal_line_items", "products", on_delete: :restrict
  add_foreign_key "deal_line_items", "tenants", on_delete: :cascade
  add_foreign_key "deals", "campaigns", column: "first_touch_campaign_id"
  add_foreign_key "deals", "contacts"
  add_foreign_key "deals", "leads"
  add_foreign_key "deals", "organisations"
  add_foreign_key "deals", "pipeline_stages"
  add_foreign_key "deals", "pipelines"
  add_foreign_key "deals", "price_books", on_delete: :nullify
  add_foreign_key "deals", "tenants"
  add_foreign_key "deals", "users", column: "owner_id"
  add_foreign_key "decision_appeals", "contacts", column: "appellant_id"
  add_foreign_key "decision_appeals", "decisions"
  add_foreign_key "decision_appeals", "tenants"
  add_foreign_key "decision_appeals", "users", column: "reviewed_by_id"
  add_foreign_key "decisions", "tenants"
  add_foreign_key "deliverable_studies", "deliverables", on_delete: :cascade
  add_foreign_key "deliverable_studies", "tenants", on_delete: :cascade
  add_foreign_key "deliverable_studies", "work_items", on_delete: :cascade
  add_foreign_key "deliverables", "deals", on_delete: :cascade
  add_foreign_key "deliverables", "projects", on_delete: :nullify
  add_foreign_key "deliverables", "tenants", on_delete: :cascade
  add_foreign_key "deliverables", "users", column: "approved_by_id", on_delete: :nullify
  add_foreign_key "deliverables", "users", column: "submitted_by_id", on_delete: :nullify
  add_foreign_key "entitlements", "contacts"
  add_foreign_key "entitlements", "organisations"
  add_foreign_key "entitlements", "sla_policies"
  add_foreign_key "entitlements", "tenants"
  add_foreign_key "escalation_executions", "cases", on_delete: :cascade
  add_foreign_key "escalation_executions", "escalation_levels", on_delete: :cascade
  add_foreign_key "escalation_executions", "tenants", on_delete: :cascade
  add_foreign_key "escalation_levels", "escalation_rules", on_delete: :cascade
  add_foreign_key "escalation_levels", "tenants", on_delete: :cascade
  add_foreign_key "escalation_levels", "users", column: "notify_user_id", on_delete: :nullify
  add_foreign_key "escalation_levels", "users", column: "then_assignee_id", on_delete: :nullify
  add_foreign_key "escalation_rules", "tenants", on_delete: :cascade
  add_foreign_key "import_conflicts", "import_identities"
  add_foreign_key "import_conflicts", "import_runs"
  add_foreign_key "import_conflicts", "tenants"
  add_foreign_key "import_identities", "import_runs", column: "last_seen_run_id"
  add_foreign_key "import_identities", "tenants"
  add_foreign_key "import_runs", "tenants"
  add_foreign_key "knowledge_categories", "knowledge_categories", column: "parent_id"
  add_foreign_key "knowledge_categories", "tenants"
  add_foreign_key "lead_capture_forms", "campaigns"
  add_foreign_key "lead_capture_forms", "tenants", on_delete: :cascade
  add_foreign_key "lead_routing_rules", "tenants", on_delete: :cascade
  add_foreign_key "lead_routing_rules", "users", column: "then_owner_id", on_delete: :nullify
  add_foreign_key "lead_scorecards", "tenants", on_delete: :cascade
  add_foreign_key "leads", "campaigns", column: "first_touch_campaign_id"
  add_foreign_key "leads", "contacts"
  add_foreign_key "leads", "deals", column: "converted_deal_id"
  add_foreign_key "leads", "leads", column: "merged_into_id", on_delete: :restrict
  add_foreign_key "leads", "tenants"
  add_foreign_key "leads", "users", column: "owner_id"
  add_foreign_key "legal_holds", "tenants"
  add_foreign_key "legal_holds", "users", column: "placed_by_id"
  add_foreign_key "legal_holds", "users", column: "released_by_id"
  add_foreign_key "macros", "queues", column: "set_queue_id", on_delete: :nullify
  add_foreign_key "macros", "tenants"
  add_foreign_key "macros", "users", column: "set_assignee_id", on_delete: :nullify
  add_foreign_key "messages", "cases"
  add_foreign_key "messages", "connectors", column: "source_connector_id"
  add_foreign_key "messages", "tenants"
  add_foreign_key "notifications", "tenants"
  add_foreign_key "notifications", "users"
  add_foreign_key "oauth_access_tokens", "service_accounts"
  add_foreign_key "organisations", "organisations", column: "parent_id", on_delete: :nullify
  add_foreign_key "organisations", "tenants"
  add_foreign_key "pipeline_stages", "pipelines"
  add_foreign_key "pipelines", "tenants"
  add_foreign_key "price_book_entries", "price_books", on_delete: :cascade
  add_foreign_key "price_book_entries", "products", on_delete: :cascade
  add_foreign_key "price_book_entries", "tenants", on_delete: :cascade
  add_foreign_key "price_books", "tenants", on_delete: :cascade
  add_foreign_key "privacy_erasure_requests", "tenants"
  add_foreign_key "privacy_erasure_requests", "users", column: "requested_by_id"
  add_foreign_key "products", "tenants", on_delete: :cascade
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "tenants"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "project_template_items", "project_templates", on_delete: :cascade
  add_foreign_key "project_template_items", "tenants", on_delete: :cascade
  add_foreign_key "project_templates", "tenants", on_delete: :cascade
  add_foreign_key "projects", "deals", column: "onboarding_deal_id", on_delete: :restrict
  add_foreign_key "projects", "project_templates", on_delete: :nullify
  add_foreign_key "projects", "tenants"
  add_foreign_key "projects", "users", column: "lead_id"
  add_foreign_key "queue_memberships", "queues"
  add_foreign_key "queue_memberships", "users"
  add_foreign_key "queues", "tenants"
  add_foreign_key "quote_line_items", "quotes", on_delete: :cascade
  add_foreign_key "quote_line_items", "tenants", on_delete: :cascade
  add_foreign_key "quote_milestones", "quotes", on_delete: :cascade
  add_foreign_key "quote_milestones", "tenants", on_delete: :cascade
  add_foreign_key "quotes", "deals", on_delete: :cascade
  add_foreign_key "quotes", "deliverables", on_delete: :nullify
  add_foreign_key "quotes", "quotes", column: "supersedes_id", on_delete: :nullify
  add_foreign_key "quotes", "tenants", on_delete: :cascade
  add_foreign_key "reference_doc_ratings", "reference_doc_versions"
  add_foreign_key "reference_doc_ratings", "reference_docs"
  add_foreign_key "reference_doc_ratings", "tenants"
  add_foreign_key "reference_doc_versions", "knowledge_categories", on_delete: :nullify
  add_foreign_key "reference_doc_versions", "reference_docs"
  add_foreign_key "reference_doc_versions", "tenants"
  add_foreign_key "reference_doc_versions", "users", column: "created_by_id"
  add_foreign_key "reference_docs", "categories"
  add_foreign_key "reference_docs", "knowledge_categories", on_delete: :nullify
  add_foreign_key "reference_docs", "reference_doc_versions", column: "current_version_id", on_delete: :nullify
  add_foreign_key "reference_docs", "tenants"
  add_foreign_key "routing_rule_executions", "cases", on_delete: :cascade
  add_foreign_key "routing_rule_executions", "routing_rules", on_delete: :nullify
  add_foreign_key "routing_rule_executions", "tenants", on_delete: :cascade
  add_foreign_key "routing_rules", "categories", column: "match_category_id"
  add_foreign_key "routing_rules", "categories", column: "then_category_id"
  add_foreign_key "routing_rules", "queues", column: "then_queue_id"
  add_foreign_key "routing_rules", "tenants"
  add_foreign_key "routing_rules", "users", column: "then_assignee_id"
  add_foreign_key "saved_views", "tenants"
  add_foreign_key "saved_views", "users"
  add_foreign_key "security_events", "tenants"
  add_foreign_key "sequence_deliveries", "activities"
  add_foreign_key "sequence_deliveries", "connectors"
  add_foreign_key "sequence_deliveries", "sequence_enrollments"
  add_foreign_key "sequence_deliveries", "sequence_steps"
  add_foreign_key "sequence_deliveries", "tenants"
  add_foreign_key "sequence_enrollments", "sequence_steps", column: "current_step_id", on_delete: :nullify
  add_foreign_key "sequence_enrollments", "sequences"
  add_foreign_key "sequence_enrollments", "tenants"
  add_foreign_key "sequence_steps", "sequences"
  add_foreign_key "sequences", "business_calendars"
  add_foreign_key "sequences", "tenants"
  add_foreign_key "sequences", "users", column: "owner_id"
  add_foreign_key "service_account_connector_grants", "connectors", on_delete: :cascade
  add_foreign_key "service_account_connector_grants", "service_accounts", on_delete: :cascade
  add_foreign_key "service_account_connector_grants", "tenants", on_delete: :cascade
  add_foreign_key "service_accounts", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "shared_credentials", "tenants"
  add_foreign_key "sla_clock_events", "cases"
  add_foreign_key "sla_clock_events", "tenants"
  add_foreign_key "sla_policies", "business_calendars"
  add_foreign_key "sla_policies", "tenants"
  add_foreign_key "sla_targets", "sla_policies"
  add_foreign_key "sprints", "projects"
  add_foreign_key "sprints", "tenants"
  add_foreign_key "tenant_export_receipts", "tenants"
  add_foreign_key "users", "tenants"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
  add_foreign_key "webhook_endpoints", "tenants"
  add_foreign_key "work_assignment_rules", "projects", on_delete: :cascade
  add_foreign_key "work_assignment_rules", "tenants", on_delete: :cascade
  add_foreign_key "work_assignment_rules", "users", column: "assignee_id", on_delete: :cascade
  add_foreign_key "work_comments", "tenants"
  add_foreign_key "work_comments", "work_items"
  add_foreign_key "work_item_relations", "tenants", on_delete: :cascade
  add_foreign_key "work_item_relations", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "work_item_relations", "work_items", column: "source_id", on_delete: :cascade
  add_foreign_key "work_item_relations", "work_items", column: "target_id", on_delete: :cascade
  add_foreign_key "work_items", "projects"
  add_foreign_key "work_items", "sprints"
  add_foreign_key "work_items", "tenants"
  add_foreign_key "work_items", "users", column: "assignee_id"
  add_foreign_key "work_items", "users", column: "reporter_id"
  add_foreign_key "work_items", "work_items", column: "parent_id"
  add_foreign_key "work_items", "workflow_states"
  add_foreign_key "work_links", "tenants"
  add_foreign_key "work_links", "users", column: "created_by_id"
  add_foreign_key "work_links", "work_items"
  add_foreign_key "work_watches", "tenants"
  add_foreign_key "work_watches", "users"
  add_foreign_key "work_watches", "work_items"
  add_foreign_key "workflow_states", "projects"
  add_foreign_key "workflow_states", "tenants"
end
