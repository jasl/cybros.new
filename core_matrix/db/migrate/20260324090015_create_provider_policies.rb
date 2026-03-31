class CreateProviderPolicies < ActiveRecord::Migration[8.2]
  def change
    create_table :provider_policies do |t|
      t.references :installation, null: false, foreign_key: true
      t.string :provider_handle, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :selection_defaults, null: false, default: {}

      t.timestamps
    end

    add_index :provider_policies, [:installation_id, :provider_handle], unique: true
  end
end
