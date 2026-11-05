class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    # Who changed what. The plan calls the details column "changes", but that name is
    # already a built-in Active Record method, so it is stored as "details".
    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true # who made the change
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, [ :target_type, :target_id ]
    add_index :audit_logs, :created_at
  end
end
