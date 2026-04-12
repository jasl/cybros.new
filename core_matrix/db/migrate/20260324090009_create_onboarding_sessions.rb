class CreateOnboardingSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :onboarding_sessions do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.string :target_kind, null: false
      t.belongs_to :target_agent, foreign_key: { to_table: :agents }
      t.belongs_to :target_execution_runtime, foreign_key: { to_table: :execution_runtimes }
      t.belongs_to :issued_by_user, foreign_key: { to_table: :users }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :token_digest, null: false
      t.string :status, null: false, default: "issued"
      t.datetime :issued_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.datetime :runtime_registered_at
      t.datetime :agent_registered_at
      t.datetime :closed_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :onboarding_sessions, :public_id, unique: true
    add_index :onboarding_sessions, :token_digest, unique: true
    add_index :onboarding_sessions,
      [:installation_id, :target_kind, :expires_at],
      name: "idx_onboarding_sessions_installation_kind_expiry"
  end
end
