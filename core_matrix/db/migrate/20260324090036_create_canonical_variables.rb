class CreateCanonicalVariables < ActiveRecord::Migration[8.2]
  def change
    create_table :canonical_variables do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.string :scope, null: false
      t.string :key, null: false
      t.jsonb :typed_value_payload, null: false, default: {}
      t.string :writer_type
      t.bigint :writer_id
      t.string :source_kind, null: false
      t.references :source_conversation, foreign_key: { to_table: :conversations }
      t.references :source_turn, foreign_key: { to_table: :turns }
      t.references :source_workflow_run, foreign_key: { to_table: :workflow_runs }
      t.string :projection_policy, null: false, default: "silent"
      t.boolean :current, null: false, default: true
      t.datetime :superseded_at
      t.references :superseded_by, foreign_key: { to_table: :canonical_variables }

      t.timestamps
    end

    add_index :canonical_variables, [:writer_type, :writer_id], name: "idx_canonical_variables_writer"
    add_index :canonical_variables,
      [:workspace_id, :key],
      unique: true,
      where: "scope = 'workspace' AND current = true",
      name: "idx_canonical_variables_workspace_current"
    add_index :canonical_variables,
      [:conversation_id, :key],
      unique: true,
      where: "scope = 'conversation' AND current = true",
      name: "idx_canonical_variables_conversation_current"
  end
end
