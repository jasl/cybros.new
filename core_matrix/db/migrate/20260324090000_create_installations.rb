class CreateInstallations < ActiveRecord::Migration[8.2]
  def change
    create_table :installations do |t|
      t.string :name, null: false
      t.string :bootstrap_state, null: false, default: "pending"
      t.jsonb :global_settings, null: false, default: {}

      t.timestamps
    end
  end
end
