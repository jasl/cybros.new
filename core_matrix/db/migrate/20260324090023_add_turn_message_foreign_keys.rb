class AddTurnMessageForeignKeys < ActiveRecord::Migration[8.2]
  def change
    change_table :turns, bulk: true do |t|
      t.references :selected_input_message, foreign_key: { to_table: :messages }
      t.references :selected_output_message, foreign_key: { to_table: :messages }
    end
  end
end
