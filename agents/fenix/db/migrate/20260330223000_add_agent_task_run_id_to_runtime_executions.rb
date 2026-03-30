class AddAgentTaskRunIdToRuntimeExecutions < ActiveRecord::Migration[8.2]
  def change
    add_column :runtime_executions, :agent_task_run_id, :string
    add_index :runtime_executions, [:agent_task_run_id, :status]
  end
end
