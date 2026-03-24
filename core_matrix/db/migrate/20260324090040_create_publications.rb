class CreatePublications < ActiveRecord::Migration[8.2]
  def change
    create_table :publications do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :owner_user, null: false, foreign_key: { to_table: :users }
      t.string :visibility_mode, null: false, default: "disabled"
      t.string :slug, null: false
      t.string :access_token_digest, null: false
      t.datetime :published_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :publications, :conversation_id, unique: true, name: "idx_publications_conversation_unique"
    add_index :publications, :slug, unique: true
    add_index :publications, :access_token_digest, unique: true
  end
end
