class CreateIdentities < ActiveRecord::Migration[8.2]
  def change
    create_table :identities do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.jsonb :auth_metadata, null: false, default: {}
      t.datetime :disabled_at

      t.timestamps
    end

    add_index :identities, :email, unique: true
  end
end
