class UnifyConversationExportRequests < ActiveRecord::Migration[8.2]
  def up
    add_column :conversation_export_requests, :request_kind, :string, null: false, default: "conversation_export"

    execute <<~SQL
      INSERT INTO conversation_export_requests (
        installation_id,
        workspace_id,
        conversation_id,
        user_id,
        public_id,
        request_kind,
        lifecycle_state,
        request_payload,
        result_payload,
        failure_payload,
        queued_at,
        started_at,
        finished_at,
        expires_at,
        created_at,
        updated_at
      )
      SELECT
        installation_id,
        workspace_id,
        conversation_id,
        user_id,
        public_id,
        'debug_export',
        lifecycle_state,
        request_payload,
        result_payload,
        failure_payload,
        queued_at,
        started_at,
        finished_at,
        expires_at,
        created_at,
        updated_at
      FROM conversation_debug_export_requests
    SQL

    execute <<~SQL
      UPDATE active_storage_attachments
      SET record_type = 'ConversationExportRequest',
          record_id = unified_requests.id
      FROM conversation_export_requests AS unified_requests
      INNER JOIN conversation_debug_export_requests AS legacy_requests
        ON legacy_requests.public_id = unified_requests.public_id
      WHERE active_storage_attachments.record_type = 'ConversationDebugExportRequest'
        AND active_storage_attachments.record_id = legacy_requests.id
        AND unified_requests.request_kind = 'debug_export'
    SQL

    drop_table :conversation_debug_export_requests
  end

  def down
    create_table :conversation_debug_export_requests do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "queued"
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.jsonb :failure_payload, null: false, default: {}
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :conversation_debug_export_requests, :public_id, unique: true

    execute <<~SQL
      INSERT INTO conversation_debug_export_requests (
        installation_id,
        workspace_id,
        conversation_id,
        user_id,
        public_id,
        lifecycle_state,
        request_payload,
        result_payload,
        failure_payload,
        queued_at,
        started_at,
        finished_at,
        expires_at,
        created_at,
        updated_at
      )
      SELECT
        installation_id,
        workspace_id,
        conversation_id,
        user_id,
        public_id,
        lifecycle_state,
        request_payload,
        result_payload,
        failure_payload,
        queued_at,
        started_at,
        finished_at,
        expires_at,
        created_at,
        updated_at
      FROM conversation_export_requests
      WHERE request_kind = 'debug_export'
    SQL

    execute <<~SQL
      UPDATE active_storage_attachments
      SET record_type = 'ConversationDebugExportRequest',
          record_id = recreated_debug_requests.id
      FROM conversation_debug_export_requests AS recreated_debug_requests
      INNER JOIN conversation_export_requests AS unified_requests
        ON unified_requests.public_id = recreated_debug_requests.public_id
      WHERE active_storage_attachments.record_type = 'ConversationExportRequest'
        AND active_storage_attachments.record_id = unified_requests.id
        AND unified_requests.request_kind = 'debug_export'
    SQL

    execute <<~SQL
      DELETE FROM conversation_export_requests
      WHERE request_kind = 'debug_export'
    SQL
    remove_column :conversation_export_requests, :request_kind
  end
end
