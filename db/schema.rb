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

ActiveRecord::Schema[8.1].define(version: 2026_10_04_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_logs", force: :cascade do |t|
    t.bigint "user_id"
    t.string "action", null: false
    t.string "auditable_type"
    t.bigint "auditable_id"
    t.string "ip"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "login_events", force: :cascade do |t|
    t.bigint "user_id"
    t.string "email_address", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.boolean "success", default: false, null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_login_events_on_created_at"
    t.index ["email_address"], name: "index_login_events_on_email_address"
    t.index ["user_id"], name: "index_login_events_on_user_id"
  end

  create_table "password_histories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "pdf_blobs", force: :cascade do |t|
    t.bigint "pdf_split_job_id", null: false
    t.bigint "pdf_split_output_id"
    t.string "kind", null: false
    t.binary "data"
    t.integer "byte_size", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "r2_key"
    t.string "checksum"
    t.datetime "r2_migrated_at"
    t.index ["expires_at"], name: "index_pdf_blobs_on_expires_at"
    t.index ["pdf_split_job_id", "kind"], name: "index_pdf_blobs_on_pdf_split_job_id_and_kind"
    t.index ["pdf_split_job_id"], name: "index_pdf_blobs_on_pdf_split_job_id"
    t.index ["pdf_split_output_id"], name: "index_pdf_blobs_on_pdf_split_output_id"
    t.index ["r2_key"], name: "index_pdf_blobs_on_r2_key", unique: true
  end

  create_table "pdf_split_jobs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "original_filename", null: false
    t.integer "page_count"
    t.integer "status", default: 0, null: false
    t.integer "pattern"
    t.float "confidence"
    t.jsonb "boundaries", default: [], null: false
    t.text "error_message"
    t.integer "output_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_pdf_split_jobs_on_created_at"
    t.index ["status"], name: "index_pdf_split_jobs_on_status"
    t.index ["user_id"], name: "index_pdf_split_jobs_on_user_id"
  end

  create_table "pdf_split_outputs", force: :cascade do |t|
    t.bigint "pdf_split_job_id", null: false
    t.string "display_name", null: false
    t.integer "page_from", null: false
    t.integer "page_to", null: false
    t.string "round_label"
    t.string "section_kind"
    t.integer "position", default: 0, null: false
    t.integer "byte_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pdf_split_job_id"], name: "index_pdf_split_outputs_on_pdf_split_job_id"
  end

  create_table "pdf_split_page_analyses", force: :cascade do |t|
    t.bigint "pdf_split_job_id", null: false
    t.integer "page", null: false
    t.string "raw_text"
    t.string "round_label"
    t.string "section_kind"
    t.boolean "is_heading", default: false, null: false
    t.float "score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pdf_split_job_id", "page"], name: "index_pdf_split_page_analyses_on_pdf_split_job_id_and_page", unique: true
    t.index ["pdf_split_job_id"], name: "index_pdf_split_page_analyses_on_pdf_split_job_id"
  end

  create_table "print_links", force: :cascade do |t|
    t.string "token", null: false
    t.bigint "created_by_id"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_print_links_on_created_by_id"
    t.index ["token"], name: "index_print_links_on_token", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "student_weekdays", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.integer "weekday", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["student_id", "weekday"], name: "index_student_weekdays_on_student_id_and_weekday", unique: true
    t.index ["student_id"], name: "index_student_weekdays_on_student_id"
  end

  create_table "students", force: :cascade do |t|
    t.string "name", null: false
    t.string "grade"
    t.date "enrolled_on"
    t.date "left_on"
    t.text "note"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_students_on_name"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name", null: false
    t.integer "role", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_until"
    t.integer "status", default: 0, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "wordbooks", force: :cascade do |t|
    t.string "name", null: false
    t.integer "words_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_wordbooks_on_name", unique: true
  end

  create_table "words", force: :cascade do |t|
    t.bigint "wordbook_id", null: false
    t.integer "number", null: false
    t.string "term", null: false
    t.text "meaning", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["wordbook_id", "number"], name: "index_words_on_wordbook_id_and_number", unique: true
    t.index ["wordbook_id"], name: "index_words_on_wordbook_id"
  end

  add_foreign_key "audit_logs", "users"
  add_foreign_key "login_events", "users", on_delete: :nullify
  add_foreign_key "password_histories", "users"
  add_foreign_key "pdf_blobs", "pdf_split_jobs", on_delete: :cascade
  add_foreign_key "pdf_blobs", "pdf_split_outputs", on_delete: :cascade
  add_foreign_key "pdf_split_jobs", "users"
  add_foreign_key "pdf_split_outputs", "pdf_split_jobs", on_delete: :cascade
  add_foreign_key "pdf_split_page_analyses", "pdf_split_jobs", on_delete: :cascade
  add_foreign_key "print_links", "users", column: "created_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "student_weekdays", "students"
  add_foreign_key "words", "wordbooks"
end
