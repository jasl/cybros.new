class CreateConversationImports < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_imports do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :source_conversation, foreign_key: { to_table: :conversations }
      t.references :source_message, foreign_key: { to_table: :messages }
      t.references :summary_segment
      t.string :kind, null: false

      t.timestamps
    end

    add_index :conversation_imports, [:conversation_id, :kind]
  end
end
