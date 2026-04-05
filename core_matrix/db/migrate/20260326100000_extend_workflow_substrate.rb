class ExtendWorkflowSubstrate < ActiveRecord::Migration[8.2]
  def change
    change_table :workflow_runs, bulk: true do |t|
      t.string :resume_policy
      t.string :resume_batch_id
      t.string :resume_yielding_node_key
      t.string :resume_successor_node_key
      t.string :resume_successor_node_type
    end

    add_check_constraint :workflow_runs,
      "(resume_policy IS NULL OR resume_policy IN ('re_enter_agent'))",
      name: "chk_workflow_runs_resume_policy"

    change_table :workflow_nodes, bulk: true do |t|
      t.references :workspace, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :turn, foreign_key: true
      t.references :yielding_workflow_node, foreign_key: { to_table: :workflow_nodes }
      t.string :intent_kind
      t.integer :stage_index
      t.integer :stage_position
      t.string :presentation_policy
    end

    add_index :workflow_nodes,
      [:workflow_run_id, :stage_index, :stage_position],
      name: "index_workflow_nodes_on_run_stage_order"
    add_check_constraint :workflow_nodes,
      "(presentation_policy IN ('internal_only', 'ops_trackable', 'user_projectable'))",
      name: "chk_workflow_nodes_presentation_policy"

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
    add_check_constraint :workflow_artifacts,
      "(presentation_policy IN ('internal_only', 'ops_trackable', 'user_projectable'))",
      name: "chk_workflow_artifacts_presentation_policy"

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
    add_check_constraint :workflow_node_events,
      "(presentation_policy IN ('internal_only', 'ops_trackable', 'user_projectable'))",
      name: "chk_workflow_node_events_presentation_policy"
  end
end
