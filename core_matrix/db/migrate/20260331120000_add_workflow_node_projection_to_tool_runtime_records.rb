class AddWorkflowNodeProjectionToToolRuntimeRecords < ActiveRecord::Migration[8.0]
  def change
    change_column_null :tool_bindings, :agent_task_run_id, true
    add_reference :tool_bindings, :workflow_node, foreign_key: true
    add_index :tool_bindings,
      [:workflow_node_id, :tool_definition_id],
      unique: true,
      where: "workflow_node_id IS NOT NULL AND agent_task_run_id IS NULL",
      name: "idx_tool_bindings_node_definition"

    change_column_null :tool_invocations, :agent_task_run_id, true
    add_reference :tool_invocations, :workflow_node, foreign_key: true

    change_column_null :command_runs, :agent_task_run_id, true
    add_reference :command_runs, :workflow_node, foreign_key: true
  end
end
