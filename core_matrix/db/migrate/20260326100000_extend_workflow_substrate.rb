class ExtendWorkflowSubstrate < ActiveRecord::Migration[8.2]
  def change
    change_table :workflow_runs, bulk: true do |t|
      t.string :resume_policy
      t.string :resume_batch_id
      t.string :resume_yielding_node_key
      t.string :resume_successor_node_key
      t.string :resume_successor_node_type
    end

    change_table :workflow_nodes, bulk: true do |t|
      t.references :yielding_workflow_node, foreign_key: { to_table: :workflow_nodes }
      t.references :opened_human_interaction_request, foreign_key: { to_table: :human_interaction_requests }
      t.references :spawned_subagent_connection, foreign_key: { to_table: :subagent_connections }
      t.string :intent_kind
      t.integer :provider_round_index
      t.text :prior_tool_node_keys, array: true, null: false, default: []
      t.string :blocked_retry_failure_kind
      t.integer :blocked_retry_attempt_no
      t.boolean :transcript_side_effect_committed, null: false, default: false
      t.integer :stage_index
      t.integer :stage_position
      t.string :presentation_policy
    end

    add_index :workflow_nodes,
      [:workflow_run_id, :stage_index, :stage_position],
      name: "index_workflow_nodes_on_run_stage_order"

    change_table :workflow_artifacts, bulk: true do |t|
      t.references :workspace, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :turn, foreign_key: true
      t.string :workflow_node_key
      t.integer :workflow_node_ordinal
      t.string :presentation_policy
    end

    add_index :workflow_artifacts,
      [:conversation_id, :workflow_node_ordinal, :artifact_kind],
      name: "index_workflow_artifacts_on_conversation_node_ordinal_kind"

    change_table :workflow_node_events, bulk: true do |t|
      t.references :workspace, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :turn, foreign_key: true
      t.string :workflow_node_key
      t.integer :workflow_node_ordinal
      t.string :presentation_policy
    end

    add_index :workflow_node_events,
      [:conversation_id, :workflow_node_ordinal, :ordinal],
      name: "index_workflow_node_events_on_conversation_node_ordinal"
  end
end
