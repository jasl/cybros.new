class CreateJsonDocuments < ActiveRecord::Migration[8.2]
  def change
    create_table :json_documents do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :document_kind, null: false
      t.string :content_sha256, null: false
      t.integer :content_bytesize, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :json_documents, :public_id, unique: true
    add_index :json_documents,
      [:installation_id, :document_kind, :content_sha256],
      unique: true,
      name: "idx_json_documents_identity"
    add_check_constraint :json_documents,
      "(content_bytesize >= 0 AND content_bytesize <= 8388608)",
      name: "chk_json_documents_content_bytesize"
  end
end
