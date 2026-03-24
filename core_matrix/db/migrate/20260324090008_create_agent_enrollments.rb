class CreateAgentEnrollments < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_enrollments do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :agent_installation, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :agent_enrollments, :token_digest, unique: true
    add_index :agent_enrollments, [:installation_id, :agent_installation_id, :expires_at], name: "index_agent_enrollments_on_installation_agent_and_expiry"
  end
end
