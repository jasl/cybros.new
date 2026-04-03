class AllowWaitingWorkflowNodes < ActiveRecord::Migration[8.2]
  def change
    remove_check_constraint :workflow_nodes, name: "chk_workflow_nodes_lifecycle_state"
    add_check_constraint :workflow_nodes,
      "(lifecycle_state IN ('pending', 'queued', 'running', 'waiting', 'completed', 'failed', 'canceled'))",
      name: "chk_workflow_nodes_lifecycle_state"
  end
end
