class CreateConversationClosures < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_closures do |t|
      t.references :installation, null: false, foreign_key: true
      t.belongs_to :ancestor_conversation, null: false, foreign_key: { to_table: :conversations }
      t.belongs_to :descendant_conversation, null: false, foreign_key: { to_table: :conversations }
      t.integer :depth, null: false

      t.timestamps
    end

    add_index :conversation_closures,
      [:installation_id, :ancestor_conversation_id, :descendant_conversation_id],
      unique: true,
      name: "idx_conversation_closures_installation_ancestor_descendant"
  end
end
