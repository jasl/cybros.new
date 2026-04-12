class AddFeaturePolicyToConversationsAndWork < ActiveRecord::Migration[8.2]
  def change
    change_table :conversations, bulk: true do |t|
      t.string :enabled_feature_ids, array: true, null: false, default: []
      t.string :during_generation_input_policy, null: false, default: "queue"
    end
  end
end
