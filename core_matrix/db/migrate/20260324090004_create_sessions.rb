class CreateSessions < ActiveRecord::Migration[8.2]
  def change
    create_table :sessions do |t|
      t.belongs_to :identity, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :sessions, :token_digest, unique: true
    add_index :sessions, :public_id, unique: true
    add_index :sessions, [:user_id, :expires_at]
  end
end
