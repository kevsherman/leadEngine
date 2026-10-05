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

ActiveRecord::Schema[8.1].define(version: 2026_10_05_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "operator_id"
    t.string "action", null: false
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_audit_events_on_conversation_id"
    t.index ["operator_id"], name: "index_audit_events_on_operator_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "source_id", null: false
    t.string "customer_name", null: false
    t.string "customer_email", null: false
    t.string "subject", null: false
    t.string "project"
    t.string "category"
    t.string "language", default: "English", null: false
    t.string "status", default: "needs_review", null: false
    t.string "next_action", null: false
    t.jsonb "known_fields", default: {}, null: false
    t.jsonb "missing_fields", default: [], null: false
    t.datetime "last_activity_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "gmail_connection_id"
    t.string "email_provider", default: "fake", null: false
    t.string "gmail_thread_id"
    t.index ["gmail_connection_id", "gmail_thread_id"], name: "index_conversations_on_gmail_connection_id_and_gmail_thread_id"
    t.index ["gmail_connection_id"], name: "index_conversations_on_gmail_connection_id"
    t.index ["source_id"], name: "index_conversations_on_source_id", unique: true
  end

  create_table "email_drafts", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "to", null: false
    t.string "cc"
    t.string "subject", null: false
    t.text "body", null: false
    t.string "status", default: "editing", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "approved_by_id"
    t.bigint "approved_message_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "approval_provider"
    t.integer "approval_connection_version"
    t.index ["approved_by_id"], name: "index_email_drafts_on_approved_by_id"
    t.index ["approved_message_id"], name: "index_email_drafts_on_approved_message_id"
    t.index ["conversation_id"], name: "index_email_drafts_on_conversation_id"
  end

  create_table "fake_deliveries", force: :cascade do |t|
    t.bigint "send_operation_id", null: false
    t.string "provider_message_id", null: false
    t.jsonb "payload", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_message_id"], name: "index_fake_deliveries_on_provider_message_id", unique: true
    t.index ["send_operation_id"], name: "index_fake_deliveries_on_send_operation_id", unique: true
  end

  create_table "gmail_connections", force: :cascade do |t|
    t.string "mailbox", null: false
    t.string "client_id"
    t.text "client_secret"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "expires_at"
    t.string "status", default: "needs_authorization", null: false
    t.boolean "polling_enabled", default: false, null: false
    t.boolean "sending_enabled", default: false, null: false
    t.boolean "alias_confirmed", default: false, null: false
    t.datetime "alias_verified_at"
    t.integer "authorization_version", default: 0, null: false
    t.integer "poll_interval_seconds", default: 60, null: false
    t.string "shopify_senders", default: "mailer@shopify.com", null: false
    t.date "import_since", null: false
    t.string "history_id"
    t.datetime "last_attempt_at"
    t.datetime "last_synced_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mailbox"], name: "index_gmail_connections_on_mailbox", unique: true
  end

  create_table "gmail_review_items", force: :cascade do |t|
    t.bigint "gmail_connection_id", null: false
    t.string "provider_message_id", null: false
    t.string "thread_id", null: false
    t.string "reason", null: false
    t.boolean "resolved", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gmail_connection_id", "provider_message_id"], name: "index_gmail_reviews_on_connection_message", unique: true
    t.index ["gmail_connection_id"], name: "index_gmail_review_items_on_gmail_connection_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "provider_id", null: false
    t.string "direction", null: false
    t.string "sender", null: false
    t.string "recipient"
    t.string "subject", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "gmail_connection_id"
    t.string "provider_thread_id"
    t.string "rfc_message_id"
    t.string "reply_to"
    t.string "cc"
    t.jsonb "references_header", default: [], null: false
    t.jsonb "attachments", default: [], null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["gmail_connection_id", "rfc_message_id"], name: "index_messages_on_gmail_connection_id_and_rfc_message_id"
    t.index ["gmail_connection_id"], name: "index_messages_on_gmail_connection_id"
    t.index ["provider_id"], name: "index_messages_on_provider_id", unique: true
  end

  create_table "operators", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_operators_on_email", unique: true
  end

  create_table "send_operations", force: :cascade do |t|
    t.bigint "email_draft_id", null: false
    t.string "status", null: false
    t.jsonb "payload", null: false
    t.string "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", default: "fake", null: false
    t.bigint "gmail_connection_id"
    t.integer "authorization_version"
    t.string "rfc_message_id"
    t.string "provider_message_id"
    t.string "provider_thread_id"
    t.bigint "requested_by_id"
    t.index ["email_draft_id"], name: "index_send_operations_on_email_draft_id", unique: true
    t.index ["gmail_connection_id"], name: "index_send_operations_on_gmail_connection_id"
    t.index ["rfc_message_id"], name: "index_send_operations_on_rfc_message_id", unique: true
  end

  add_foreign_key "audit_events", "conversations"
  add_foreign_key "audit_events", "operators"
  add_foreign_key "conversations", "gmail_connections"
  add_foreign_key "email_drafts", "conversations"
  add_foreign_key "email_drafts", "messages", column: "approved_message_id"
  add_foreign_key "email_drafts", "operators", column: "approved_by_id"
  add_foreign_key "fake_deliveries", "send_operations"
  add_foreign_key "gmail_review_items", "gmail_connections"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "gmail_connections"
  add_foreign_key "send_operations", "email_drafts"
  add_foreign_key "send_operations", "gmail_connections"
  add_foreign_key "send_operations", "operators", column: "requested_by_id"
end
