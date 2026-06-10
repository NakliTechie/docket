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

ActiveRecord::Schema[8.1].define(version: 2026_06_10_141124) do
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
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cases", "categories"
  add_foreign_key "cases", "contacts"
  add_foreign_key "cases", "queues"
  add_foreign_key "cases", "sla_policies"
  add_foreign_key "cases", "users", column: "assignee_id"
  add_foreign_key "contacts", "organisations"
  add_foreign_key "messages", "cases"
  add_foreign_key "queue_memberships", "queues"
  add_foreign_key "queue_memberships", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "sla_targets", "sla_policies"
end
