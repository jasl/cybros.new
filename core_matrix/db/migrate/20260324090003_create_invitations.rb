class CreateInvitations < ActiveRecord::Migration[8.2]
  def change
    create_table :invitations do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.belongs_to :inviter, null: false, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.string :email, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    add_index :invitations, :email
  end
end
