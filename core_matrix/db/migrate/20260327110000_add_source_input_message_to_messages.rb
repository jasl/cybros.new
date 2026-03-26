class AddSourceInputMessageToMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :messages, :source_input_message, foreign_key: { to_table: :messages }
  end
end
