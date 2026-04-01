class AddEnqueuedAtToRuntimeExecutions < ActiveRecord::Migration[8.2]
  def change
    add_column :runtime_executions, :enqueued_at, :datetime
    add_index :runtime_executions, [:status, :enqueued_at]
  end
end
