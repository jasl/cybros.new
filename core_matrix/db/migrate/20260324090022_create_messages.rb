class CreateMessages < ActiveRecord::Migration[8.2]
  def change
    create_table :messages do |t|
      t.references :installation, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :turn, null: false, foreign_key: true
      t.uuid :public_id, null: false, default: -> { "uuidv7()" }
      t.string :type, null: false
      t.string :role, null: false
      t.string :slot, null: false
      t.integer :variant_index, null: false, default: 0
      t.text :content, null: false

      t.timestamps
    end

    add_index :messages, [:turn_id, :slot, :variant_index], unique: true
    add_index :messages, :public_id, unique: true
  end
end
