class AddTurnMessageForeignKeys < ActiveRecord::Migration[8.2]
  def change
    add_index :turns, :selected_input_message_id
    add_index :turns, :selected_output_message_id

    add_foreign_key :turns, :messages, column: :selected_input_message_id
    add_foreign_key :turns, :messages, column: :selected_output_message_id
  end
end
