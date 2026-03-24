class CreateAuditLogs < ActiveRecord::Migration[8.2]
  def change
    create_table :audit_logs do |t|
      t.belongs_to :installation, null: false, foreign_key: true
      t.references :actor, polymorphic: true
      t.string :action, null: false
      t.references :subject, polymorphic: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :audit_logs, [:installation_id, :action]
  end
end
