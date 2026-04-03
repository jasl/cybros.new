class AddFeaturePolicyToConversationsAndWork < ActiveRecord::Migration[8.2]
  def change
    change_table :conversations, bulk: true do |t|
      t.string :enabled_feature_ids, array: true, null: false, default: []
      t.string :during_generation_input_policy, null: false, default: "queue"
    end
    add_check_constraint :conversations,
      "(during_generation_input_policy IN ('reject', 'restart', 'queue'))",
      name: "chk_conversations_during_generation_input_policy"

    change_table :turns, bulk: true do |t|
      t.jsonb :feature_policy_snapshot, null: false, default: {}
    end
  end
end
