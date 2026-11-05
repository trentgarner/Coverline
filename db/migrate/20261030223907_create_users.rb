class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :team, foreign_key: true # agents belong to a team; managers/admins may not
      t.string :role, null: false, default: "agent" # agent | manager | admin | super_user
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :phone_agent_id # this person's login/ID in the phone system
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :users, :email_address, unique: true
    add_index :users, [ :organization_id, :phone_agent_id ], unique: true, where: "phone_agent_id IS NOT NULL"
  end
end
