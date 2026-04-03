class CreateRuntimeExecutions < ActiveRecord::Migration[8.2]
  def change
    create_table :runtime_executions do |t|
      t.string :execution_id, null: false
      t.string :mailbox_item_id, null: false
      t.string :protocol_message_id, null: false
      t.string :logical_work_id, null: false
      t.string :agent_task_run_id
      t.integer :attempt_no, null: false
      t.string :runtime_plane, null: false
      t.string :status, null: false, default: "queued"
      t.json :mailbox_item_payload, null: false, default: {}
      t.json :reports, null: false, default: []
      t.json :trace, null: false, default: []
      t.json :output_payload
      t.json :error_payload
      t.datetime :enqueued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :runtime_executions, :execution_id, unique: true
    add_index :runtime_executions, [:mailbox_item_id, :attempt_no], unique: true
    add_index :runtime_executions, [:agent_task_run_id, :status]
    add_index :runtime_executions, [:status, :enqueued_at]
  end
end
