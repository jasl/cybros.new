class CreateConversationBundleImportRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_bundle_import_requests do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :imported_conversation, foreign_key: { to_table: :conversations }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :lifecycle_state, null: false, default: "queued"
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :result_payload, null: false, default: {}
      t.jsonb :failure_payload, null: false, default: {}
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :conversation_bundle_import_requests, :public_id, unique: true
  end
end
