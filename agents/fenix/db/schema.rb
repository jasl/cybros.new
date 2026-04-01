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

ActiveRecord::Schema[8.2].define(version: 2026_04_01_110500) do
  create_table "runtime_executions", force: :cascade do |t|
    t.string "agent_task_run_id"
    t.integer "attempt_no", null: false
    t.datetime "created_at", null: false
    t.datetime "enqueued_at"
    t.json "error_payload"
    t.string "execution_id", null: false
    t.datetime "finished_at"
    t.string "logical_work_id", null: false
    t.string "mailbox_item_id", null: false
    t.json "mailbox_item_payload", default: {}, null: false
    t.json "output_payload"
    t.string "protocol_message_id", null: false
    t.json "reports", default: [], null: false
    t.string "runtime_plane", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.json "trace", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["agent_task_run_id", "status"], name: "index_runtime_executions_on_agent_task_run_id_and_status"
    t.index ["execution_id"], name: "index_runtime_executions_on_execution_id", unique: true
    t.index ["mailbox_item_id", "attempt_no"], name: "index_runtime_executions_on_mailbox_item_id_and_attempt_no", unique: true
    t.index ["status", "enqueued_at"], name: "index_runtime_executions_on_status_and_enqueued_at"
  end
end
