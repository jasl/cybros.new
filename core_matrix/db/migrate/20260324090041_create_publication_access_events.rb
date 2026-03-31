class CreatePublicationAccessEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :publication_access_events do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :publication, null: false, foreign_key: true
      t.references :viewer_user, foreign_key: { to_table: :users }
      t.string :access_via, null: false
      t.datetime :accessed_at, null: false
      t.jsonb :request_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :publication_access_events, [:publication_id, :accessed_at],
              name: "idx_publication_access_events_publication_accessed_at"
  end
end
