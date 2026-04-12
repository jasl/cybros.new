class CreateAgentVersioningCore < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_definition_versions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :version, null: false
      t.string :definition_fingerprint, null: false
      t.string :program_manifest_fingerprint, null: false
      t.string :protocol_version, null: false
      t.string :sdk_version, null: false
      t.string :prompt_pack_ref, null: false
      t.string :prompt_pack_fingerprint, null: false
      t.references :protocol_methods_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :tool_contract_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :profile_policy_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :canonical_config_schema_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :conversation_override_schema_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :default_canonical_config_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :reflected_surface_document, null: false, foreign_key: { to_table: :json_documents }
      t.timestamps
    end

    add_index :agent_definition_versions, :public_id, unique: true
    add_index :agent_definition_versions,
      [:agent_id, :version],
      unique: true,
      name: "idx_agent_definition_versions_agent_version"
    add_index :agent_definition_versions,
      [:agent_id, :definition_fingerprint],
      unique: true,
      name: "idx_agent_definition_versions_agent_fingerprint"

    create_table :agent_config_states do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true, index: false
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.references :base_agent_definition_version, null: false, foreign_key: { to_table: :agent_definition_versions }
      t.integer :version, null: false, default: 1
      t.references :override_document, foreign_key: { to_table: :json_documents }
      t.references :effective_document, null: false, foreign_key: { to_table: :json_documents }
      t.string :content_fingerprint, null: false
      t.string :reconciliation_state, null: false, default: "ready"
      t.timestamps
    end

    add_index :agent_config_states, :public_id, unique: true
    add_index :agent_config_states, :agent_id, unique: true
    add_index :agent_config_states,
      [:installation_id, :content_fingerprint],
      name: "idx_agent_config_states_installation_fingerprint"

    create_table :execution_runtime_versions do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :execution_runtime, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.integer :version, null: false
      t.string :content_fingerprint, null: false
      t.string :execution_runtime_fingerprint, null: false
      t.string :kind, null: false
      t.string :protocol_version, null: false
      t.string :sdk_version, null: false
      t.references :capability_payload_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :tool_catalog_document, null: false, foreign_key: { to_table: :json_documents }
      t.references :reflected_host_metadata_document, foreign_key: { to_table: :json_documents }
      t.timestamps
    end

    add_index :execution_runtime_versions, :public_id, unique: true
    add_index :execution_runtime_versions,
      [:execution_runtime_id, :version],
      unique: true,
      name: "idx_execution_runtime_versions_runtime_version"
    add_index :execution_runtime_versions,
      [:execution_runtime_id, :content_fingerprint],
      unique: true,
      name: "idx_execution_runtime_versions_runtime_fingerprint"

    add_reference :agents,
      :published_agent_definition_version,
      foreign_key: { to_table: :agent_definition_versions }
    add_reference :execution_runtimes,
      :published_execution_runtime_version,
      foreign_key: { to_table: :execution_runtime_versions }
  end
end
