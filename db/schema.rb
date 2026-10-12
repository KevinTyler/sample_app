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

ActiveRecord::Schema[8.1].define(version: 2026_10_13_030000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "guest_id"
    t.integer "user_id"
    t.string "action", null: false
    t.json "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["event_id", "created_at"], name: "index_activities_on_event_id_and_created_at"
    t.index ["event_id"], name: "index_activities_on_event_id"
    t.index ["guest_id"], name: "index_activities_on_guest_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "cohost_invitations", force: :cascade do |t|
    t.integer "event_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token_digest", null: false
    t.integer "invited_by_id"
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "email"], name: "index_cohost_invitations_on_event_id_and_email"
    t.index ["event_id"], name: "index_cohost_invitations_on_event_id"
    t.index ["invited_by_id"], name: "index_cohost_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_cohost_invitations_on_token_digest", unique: true
  end

  create_table "deliveries", force: :cascade do |t|
    t.integer "message_id", null: false
    t.integer "guest_id", null: false
    t.string "channel", null: false
    t.string "status", default: "queued", null: false
    t.string "recipient", null: false
    t.string "provider"
    t.string "provider_message_id"
    t.string "error_message"
    t.integer "attempts", default: 0, null: false
    t.datetime "last_attempt_at"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "delivered_at"
    t.index ["guest_id"], name: "index_deliveries_on_guest_id"
    t.index ["message_id", "guest_id", "channel"], name: "index_deliveries_on_message_id_and_guest_id_and_channel", unique: true
    t.index ["message_id"], name: "index_deliveries_on_message_id"
    t.index ["provider_message_id"], name: "index_deliveries_on_provider_message_id"
    t.index ["status"], name: "index_deliveries_on_status"
  end

  create_table "event_memberships", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "user_id", null: false
    t.string "role", null: false
    t.integer "invited_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "user_id"], name: "index_event_memberships_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_memberships_on_event_id"
    t.index ["invited_by_id"], name: "index_event_memberships_on_invited_by_id"
    t.index ["user_id"], name: "index_event_memberships_on_user_id"
  end

  create_table "event_questions", force: :cascade do |t|
    t.integer "event_id", null: false
    t.string "prompt", null: false
    t.string "kind", default: "short_text", null: false
    t.json "options", default: [], null: false
    t.boolean "required", default: false, null: false
    t.string "applies_to", default: "attending", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_questions_on_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "owner_id", null: false
    t.string "title", null: false
    t.string "host_name"
    t.text "description"
    t.string "status", default: "draft", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.string "time_zone", default: "America/New_York", null: false
    t.string "location_name"
    t.string "address"
    t.string "video_url"
    t.datetime "rsvp_deadline"
    t.integer "capacity"
    t.boolean "allow_maybe", default: true, null: false
    t.boolean "allow_link_rsvp", default: false, null: false
    t.boolean "show_guest_count", default: false, null: false
    t.integer "default_plus_ones", default: 0, null: false
    t.string "share_token", null: false
    t.json "design", default: {}, null: false
    t.integer "calendar_sequence", default: 0, null: false
    t.datetime "published_at"
    t.datetime "cancelled_at"
    t.text "cancellation_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ticket_price_cents"
    t.string "currency", default: "usd", null: false
    t.index ["owner_id"], name: "index_events_on_owner_id"
    t.index ["share_token"], name: "index_events_on_share_token", unique: true
    t.index ["status"], name: "index_events_on_status"
  end

  create_table "guest_imports", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "user_id"
    t.string "filename"
    t.text "csv_data"
    t.boolean "update_existing", default: false, null: false
    t.string "status", default: "pending", null: false
    t.json "summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_guest_imports_on_event_id"
    t.index ["user_id"], name: "index_guest_imports_on_user_id"
  end

  create_table "guests", force: :cascade do |t|
    t.integer "event_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.string "group_name"
    t.integer "plus_ones_allowed", default: 0, null: false
    t.string "token_key", null: false
    t.string "rsvp_status", default: "pending", null: false
    t.integer "party_size", default: 0, null: false
    t.text "guest_note"
    t.text "host_notes"
    t.string "source", default: "manual", null: false
    t.datetime "responded_at"
    t.datetime "invited_at"
    t.datetime "first_viewed_at"
    t.datetime "last_viewed_at"
    t.datetime "checked_in_at"
    t.integer "checked_in_count", default: 0, null: false
    t.datetime "unsubscribed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "email"], name: "index_guests_on_event_id_and_email", unique: true, where: "email IS NOT NULL"
    t.index ["event_id", "group_name"], name: "index_guests_on_event_id_and_group_name"
    t.index ["event_id", "rsvp_status"], name: "index_guests_on_event_id_and_rsvp_status"
    t.index ["event_id"], name: "index_guests_on_event_id"
    t.index ["token_key"], name: "index_guests_on_token_key", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "author_id"
    t.string "kind", null: false
    t.string "subject"
    t.text "body"
    t.json "channels", default: ["email"], null: false
    t.json "audience", default: {}, null: false
    t.string "idempotency_key", null: false
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_for"
    t.datetime "dispatched_at"
    t.integer "recipients_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_messages_on_author_id"
    t.index ["event_id", "idempotency_key"], name: "index_messages_on_event_id_and_idempotency_key", unique: true
    t.index ["event_id"], name: "index_messages_on_event_id"
    t.index ["status", "scheduled_for"], name: "index_messages_on_status_and_scheduled_for"
  end

  create_table "outbox_items", force: :cascade do |t|
    t.string "channel", null: false
    t.string "recipient", null: false
    t.string "subject"
    t.text "text_body"
    t.text "html_body"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
  end

  create_table "payments", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "guest_id"
    t.integer "amount_cents", null: false
    t.string "currency", null: false
    t.integer "quantity", null: false
    t.string "status", default: "pending", null: false
    t.string "provider", null: false
    t.string "provider_session_id"
    t.string "provider_payment_id"
    t.string "checkout_url", limit: 2048
    t.string "idempotency_key", null: false
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_payments_on_event_id"
    t.index ["guest_id"], name: "index_payments_on_guest_id"
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true
    t.index ["provider", "provider_session_id"], name: "index_payments_on_provider_and_provider_session_id", unique: true
  end

  create_table "rsvp_answers", force: :cascade do |t|
    t.integer "guest_id", null: false
    t.integer "event_question_id", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_question_id"], name: "index_rsvp_answers_on_event_question_id"
    t.index ["guest_id", "event_question_id"], name: "index_rsvp_answers_on_guest_id_and_event_question_id", unique: true
    t.index ["guest_id"], name: "index_rsvp_answers_on_guest_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "events"
  add_foreign_key "activities", "guests", on_delete: :nullify
  add_foreign_key "activities", "users", on_delete: :nullify
  add_foreign_key "cohost_invitations", "events"
  add_foreign_key "cohost_invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "deliveries", "guests"
  add_foreign_key "deliveries", "messages"
  add_foreign_key "event_memberships", "events"
  add_foreign_key "event_memberships", "users"
  add_foreign_key "event_memberships", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "event_questions", "events"
  add_foreign_key "events", "users", column: "owner_id"
  add_foreign_key "guest_imports", "events"
  add_foreign_key "guest_imports", "users", on_delete: :nullify
  add_foreign_key "guests", "events"
  add_foreign_key "messages", "events"
  add_foreign_key "messages", "users", column: "author_id"
  add_foreign_key "payments", "events"
  add_foreign_key "payments", "guests", on_delete: :nullify
  add_foreign_key "rsvp_answers", "event_questions"
  add_foreign_key "rsvp_answers", "guests"
  add_foreign_key "sessions", "users"
end
