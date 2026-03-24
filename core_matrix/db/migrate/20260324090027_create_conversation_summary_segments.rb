class CreateConversationSummarySegments < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_summary_segments do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :start_message, null: false, foreign_key: { to_table: :messages }
      t.references :end_message, null: false, foreign_key: { to_table: :messages }
      t.references :superseded_by, foreign_key: { to_table: :conversation_summary_segments }
      t.text :content, null: false

      t.timestamps
    end

    add_foreign_key :conversation_imports, :conversation_summary_segments, column: :summary_segment_id
  end
end
