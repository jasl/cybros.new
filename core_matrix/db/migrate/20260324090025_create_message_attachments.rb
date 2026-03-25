class CreateMessageAttachments < ActiveRecord::Migration[8.2]
  def change
    create_table :message_attachments do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.references :origin_attachment, foreign_key: { to_table: :message_attachments }
      t.references :origin_message, foreign_key: { to_table: :messages }
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }

      t.timestamps
    end

    add_index :message_attachments, :public_id, unique: true
  end
end
