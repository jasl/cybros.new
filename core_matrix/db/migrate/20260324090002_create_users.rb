class CreateUsers < ActiveRecord::Migration[8.2]
  def change
    create_table :users do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :identity, null: false, foreign_key: true, index: { unique: true }
      t.string :role, null: false, default: "member"
      t.string :display_name, null: false
      t.jsonb :preferences, null: false, default: {}

      t.timestamps
    end

    add_index :users, [:installation_id, :role]
  end
end
