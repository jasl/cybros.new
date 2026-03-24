class CreateConversationMessageVisibilities < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_message_visibilities do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.boolean :hidden, null: false, default: false
      t.boolean :excluded_from_context, null: false, default: false

      t.timestamps
    end

    add_index :conversation_message_visibilities,
      [:conversation_id, :message_id],
      unique: true,
      name: "idx_message_visibilities_conversation_message"
  end
end
