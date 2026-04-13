class AddWorkflowBootstrapBacklogIndexToTurns < ActiveRecord::Migration[8.2]
  def change
    add_index :turns,
              [:workflow_bootstrap_state, :workflow_bootstrap_started_at],
              name: "idx_turns_workflow_bootstrap_backlog"
  end
end
