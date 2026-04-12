class AddToolGovernance < ActiveRecord::Migration[8.2]
  def change
    create_table :implementation_sources do |t|
      t.references :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :source_kind, null: false
      t.string :source_ref, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :implementation_sources, :public_id, unique: true
    add_index :implementation_sources, [:installation_id, :source_kind, :source_ref], unique: true, name: "idx_implementation_sources_identity"

    create_table :tool_definitions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent_definition_version, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :tool_name, null: false
      t.string :tool_kind, null: false
      t.string :governance_mode, null: false
      t.jsonb :policy_payload, null: false, default: {}
      t.timestamps
    end
    add_index :tool_definitions, :public_id, unique: true
    add_index :tool_definitions, [:agent_definition_version_id, :tool_name], unique: true, name: "idx_tool_definitions_definition_tool"

    create_table :tool_implementations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :tool_definition, null: false, foreign_key: true
      t.references :implementation_source, null: false, foreign_key: true
      t.references :workflow_node, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :implementation_ref, null: false
      t.jsonb :input_schema, null: false, default: {}
      t.jsonb :result_schema, null: false, default: {}
      t.boolean :streaming_support, null: false, default: false
      t.string :idempotency_policy, null: false
      t.boolean :default_for_snapshot, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :tool_implementations, :public_id, unique: true
    add_index :tool_implementations, [:tool_definition_id, :implementation_ref], unique: true, name: "idx_tool_implementations_definition_ref"
    add_index :tool_implementations, :tool_definition_id, unique: true, where: "default_for_snapshot", name: "idx_tool_implementations_one_default"

    create_table :tool_bindings do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :tool_definition, null: false, foreign_key: true
      t.references :tool_implementation, null: false, foreign_key: true
      t.references :agent_task_run, foreign_key: true
      t.references :workflow_node, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :idempotency_key
      t.string :binding_reason, null: false
      t.boolean :round_scoped, null: false, default: false
      t.boolean :parallel_safe, null: false, default: false
      t.bigint :source_tool_binding_id
      t.bigint :source_workflow_node_id
      t.string :tool_call_id
      t.jsonb :runtime_state, null: false, default: {}
      t.timestamps
    end
    add_index :tool_bindings, :public_id, unique: true
    add_index :tool_bindings, [:agent_task_run_id, :tool_definition_id], unique: true, name: "idx_tool_bindings_task_definition"
    add_index :tool_bindings, :source_tool_binding_id
    add_index :tool_bindings, :source_workflow_node_id
    add_index :tool_bindings,
              [:workflow_node_id, :tool_definition_id],
              unique: true,
              where: "workflow_node_id IS NOT NULL AND agent_task_run_id IS NULL",
              name: "idx_tool_bindings_node_definition"
    add_foreign_key :tool_bindings, :tool_bindings, column: :source_tool_binding_id
    add_foreign_key :tool_bindings, :workflow_nodes, column: :source_workflow_node_id

    create_table :tool_invocations do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :tool_binding, null: false, foreign_key: true
      t.references :tool_definition, null: false, foreign_key: true
      t.references :tool_implementation, null: false, foreign_key: true
      t.references :agent_task_run, foreign_key: true
      t.references :workflow_node, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :status, null: false
      t.string :provider_format
      t.boolean :stream_output, null: false, default: false
      t.references :request_document, foreign_key: { to_table: :json_documents }
      t.references :response_document, foreign_key: { to_table: :json_documents }
      t.references :error_document, foreign_key: { to_table: :json_documents }
      t.references :trace_document, foreign_key: { to_table: :json_documents }
      t.integer :attempt_no, null: false, default: 1
      t.string :idempotency_key
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :tool_invocations, :public_id, unique: true
    add_index :tool_invocations, [:tool_binding_id, :attempt_no], unique: true, name: "idx_tool_invocations_binding_attempt"
  end
end
