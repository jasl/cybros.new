class AddFeaturePolicyToConversationsAndWork < ActiveRecord::Migration[8.2]
  def change
    add_column :conversations, :enabled_feature_ids, :string, array: true, null: false, default: []
    add_column :conversations, :during_generation_input_policy, :string, null: false, default: "queue"
    add_check_constraint :conversations,
      "(during_generation_input_policy IN ('reject', 'restart', 'queue'))",
      name: "chk_conversations_during_generation_input_policy"

    add_column :turns, :feature_policy_snapshot, :jsonb, null: false, default: {}
    add_column :workflow_runs, :feature_policy_snapshot, :jsonb, null: false, default: {}
    add_column :agent_task_runs, :feature_policy_snapshot, :jsonb, null: false, default: {}
  end
end
