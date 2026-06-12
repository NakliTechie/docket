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

ActiveRecord::Schema[8.1].define(version: 2026_06_12_095000) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
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
    t.string "sha", limit: 64, null: false
    t.index ["action"], name: "index_audit_entries_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_entries_on_actor"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_entries_on_auditable"
    t.index ["created_at"], name: "index_audit_entries_on_created_at"
    t.index ["sha"], name: "index_audit_entries_on_sha", unique: true
  end

  create_table "cases", force: :cascade do |t|
    t.integer "assignee_id"
    t.integer "category_id"
    t.integer "channel", default: 0, null: false
    t.datetime "closed_at"
    t.integer "contact_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.datetime "first_responded_at"
    t.boolean "first_response_breached", default: false, null: false
    t.datetime "first_response_due_at"
    t.integer "lock_version", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.integer "queue_id"
    t.integer "reopen_count", default: 0, null: false
    t.datetime "reopened_at"
    t.boolean "resolution_breached", default: false, null: false
    t.datetime "resolution_due_at"
    t.datetime "resolved_at"
    t.integer "sla_policy_id"
    t.integer "status", default: 0, null: false
    t.string "subject", null: false
    t.string "tracking_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_cases_on_assignee_id"
    t.index ["category_id"], name: "index_cases_on_category_id"
    t.index ["contact_id"], name: "index_cases_on_contact_id"
    t.index ["created_at"], name: "index_cases_on_created_at"
    t.index ["deleted_at"], name: "index_cases_on_deleted_at"
    t.index ["first_response_breached", "first_response_due_at"], name: "idx_on_first_response_breached_first_response_due_a_66b2255ab2"
    t.index ["priority"], name: "index_cases_on_priority"
    t.index ["queue_id"], name: "index_cases_on_queue_id"
    t.index ["resolution_breached", "resolution_due_at"], name: "index_cases_on_resolution_breached_and_resolution_due_at"
    t.index ["sla_policy_id"], name: "index_cases_on_sla_policy_id"
    t.index ["status", "queue_id"], name: "index_cases_on_status_and_queue_id"
    t.index ["status"], name: "index_cases_on_status"
    t.index ["tracking_id"], name: "index_cases_on_tracking_id", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "ai_auto_resolve", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_categories_on_deleted_at"
    t.index ["name"], name: "index_categories_on_name", unique: true, where: "deleted_at IS NULL"
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
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_connector_invocations_on_approved_by_id"
    t.index ["connector_id", "id"], name: "index_connector_invocations_on_connector_id_and_id"
    t.index ["connector_id", "idempotency_key"], name: "index_connector_invocations_idempotency", unique: true
    t.index ["connector_id"], name: "index_connector_invocations_on_connector_id"
    t.index ["delegation_id"], name: "index_connector_invocations_on_delegation_id", unique: true
    t.index ["requested_by_type", "requested_by_id"], name: "index_connector_invocations_on_requested_by"
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
    t.integer "trigger", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["connector_id", "id"], name: "index_connector_runs_on_connector_id_and_id"
    t.index ["connector_id"], name: "index_connector_runs_on_connector_id"
  end

  create_table "connectors", force: :cascade do |t|
    t.json "auto_approve_actions"
    t.json "config"
    t.datetime "created_at", null: false
    t.text "credentials"
    t.datetime "deleted_at"
    t.json "enabled_actions"
    t.json "field_mapping"
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.string "provider", null: false
    t.integer "schedule_interval_minutes"
    t.integer "status", default: 0, null: false
    t.string "target", default: "contacts", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["deleted_at"], name: "index_connectors_on_deleted_at"
    t.index ["status"], name: "index_connectors_on_status"
  end

  create_table "contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.string "external_id"
    t.string "name", null: false
    t.text "notes"
    t.integer "organisation_id"
    t.string "phone"
    t.string "preferred_language", default: "en", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_contacts_on_deleted_at"
    t.index ["email"], name: "index_contacts_on_email"
    t.index ["external_id"], name: "index_contacts_on_external_id", unique: true, where: "external_id IS NOT NULL AND deleted_at IS NULL"
    t.index ["organisation_id"], name: "index_contacts_on_organisation_id"
    t.index ["phone"], name: "index_contacts_on_phone"
  end

  create_table "deals", force: :cascade do |t|
    t.datetime "closed_at"
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "INR", null: false
    t.datetime "deleted_at"
    t.date "expected_close_on"
    t.integer "lead_id"
    t.string "name", null: false
    t.integer "organisation_id"
    t.integer "owner_id"
    t.integer "pipeline_id", null: false
    t.integer "pipeline_stage_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "value_cents"
    t.index ["contact_id"], name: "index_deals_on_contact_id"
    t.index ["deleted_at"], name: "index_deals_on_deleted_at"
    t.index ["lead_id"], name: "index_deals_on_lead_id"
    t.index ["organisation_id"], name: "index_deals_on_organisation_id"
    t.index ["owner_id"], name: "index_deals_on_owner_id"
    t.index ["pipeline_id", "pipeline_stage_id"], name: "index_deals_on_pipeline_id_and_pipeline_stage_id"
    t.index ["pipeline_id"], name: "index_deals_on_pipeline_id"
    t.index ["pipeline_stage_id"], name: "index_deals_on_pipeline_stage_id"
    t.index ["status"], name: "index_deals_on_status"
  end

  create_table "leads", force: :cascade do |t|
    t.string "company_name"
    t.integer "contact_id"
    t.datetime "converted_at"
    t.integer "converted_deal_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.integer "owner_id"
    t.string "phone"
    t.integer "source", default: 2, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "value_estimate_cents"
    t.index ["contact_id"], name: "index_leads_on_contact_id"
    t.index ["converted_deal_id"], name: "index_leads_on_converted_deal_id"
    t.index ["deleted_at"], name: "index_leads_on_deleted_at"
    t.index ["email"], name: "index_leads_on_email"
    t.index ["owner_id"], name: "index_leads_on_owner_id"
    t.index ["status"], name: "index_leads_on_status"
  end

  create_table "macros", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_macros_on_deleted_at"
    t.index ["name"], name: "index_macros_on_name", unique: true, where: "deleted_at IS NULL"
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
    t.integer "kind", default: 0, null: false
    t.json "metadata"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_messages_on_author"
    t.index ["case_id", "created_at"], name: "index_messages_on_case_id_and_created_at"
    t.index ["case_id"], name: "index_messages_on_case_id"
    t.index ["deleted_at"], name: "index_messages_on_deleted_at"
    t.index ["email_message_id"], name: "index_messages_on_email_message_id"
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
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_organisations_on_deleted_at"
    t.index ["external_ref"], name: "index_organisations_on_external_ref"
    t.index ["name"], name: "index_organisations_on_name", unique: true, where: "deleted_at IS NULL"
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
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_pipelines_on_deleted_at"
    t.index ["slug"], name: "index_pipelines_on_slug", unique: true, where: "deleted_at IS NULL"
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
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_queues_on_deleted_at"
    t.index ["name"], name: "index_queues_on_name", unique: true, where: "deleted_at IS NULL"
    t.index ["slug"], name: "index_queues_on_slug", unique: true, where: "deleted_at IS NULL"
  end

  create_table "reference_docs", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_reference_docs_on_deleted_at"
    t.index ["title"], name: "index_reference_docs_on_title", unique: true, where: "deleted_at IS NULL"
  end

  create_table "security_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "ip_address"
    t.string "kind", null: false
    t.json "metadata"
    t.string "user_agent"
    t.index ["created_at"], name: "index_security_events_on_created_at"
    t.index ["kind"], name: "index_security_events_on_kind"
  end

  create_table "sequence_enrollments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_step_position", default: 0, null: false
    t.datetime "deleted_at"
    t.integer "enrollable_id", null: false
    t.string "enrollable_type", null: false
    t.datetime "next_run_at"
    t.integer "sequence_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sequence_enrollments_on_deleted_at"
    t.index ["enrollable_type", "enrollable_id"], name: "index_sequence_enrollments_on_enrollable"
    t.index ["sequence_id"], name: "index_sequence_enrollments_on_sequence_id"
    t.index ["status", "next_run_at"], name: "index_sequence_enrollments_on_status_and_next_run_at"
  end

  create_table "sequence_steps", force: :cascade do |t|
    t.text "body"
    t.integer "channel", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "delay_days", default: 0, null: false
    t.datetime "deleted_at"
    t.integer "position", default: 0, null: false
    t.integer "sequence_id", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sequence_steps_on_deleted_at"
    t.index ["sequence_id", "position"], name: "index_sequence_steps_on_sequence_id_and_position"
    t.index ["sequence_id"], name: "index_sequence_steps_on_sequence_id"
  end

  create_table "sequences", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sequences_on_deleted_at"
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
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_service_accounts_on_client_id", unique: true
    t.index ["deleted_at"], name: "index_service_accounts_on_deleted_at"
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
    t.datetime "updated_at", null: false
    t.json "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "sla_policies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_sla_policies_on_deleted_at"
    t.index ["name"], name: "index_sla_policies_on_name", unique: true, where: "deleted_at IS NULL"
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

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email_address", null: false
    t.string "locale"
    t.string "name", default: "", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true, where: "deleted_at IS NULL"
    t.index ["role"], name: "index_users_on_role"
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
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["deleted_at"], name: "index_webhook_endpoints_on_deleted_at"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "cases", "categories"
  add_foreign_key "cases", "contacts"
  add_foreign_key "cases", "queues"
  add_foreign_key "cases", "sla_policies"
  add_foreign_key "cases", "users", column: "assignee_id"
  add_foreign_key "connector_invocations", "connectors"
  add_foreign_key "connector_invocations", "users", column: "approved_by_id"
  add_foreign_key "connector_runs", "connectors"
  add_foreign_key "contacts", "organisations"
  add_foreign_key "deals", "contacts"
  add_foreign_key "deals", "leads"
  add_foreign_key "deals", "organisations"
  add_foreign_key "deals", "pipeline_stages"
  add_foreign_key "deals", "pipelines"
  add_foreign_key "deals", "users", column: "owner_id"
  add_foreign_key "leads", "contacts"
  add_foreign_key "leads", "deals", column: "converted_deal_id"
  add_foreign_key "leads", "users", column: "owner_id"
  add_foreign_key "messages", "cases"
  add_foreign_key "oauth_access_tokens", "service_accounts"
  add_foreign_key "pipeline_stages", "pipelines"
  add_foreign_key "queue_memberships", "queues"
  add_foreign_key "queue_memberships", "users"
  add_foreign_key "sequence_enrollments", "sequences"
  add_foreign_key "sequence_steps", "sequences"
  add_foreign_key "sessions", "users"
  add_foreign_key "sla_targets", "sla_policies"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
end
