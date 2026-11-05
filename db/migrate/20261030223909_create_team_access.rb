class CreateTeamAccess < ActiveRecord::Migration[8.1]
  def change
    # Which teams a manager can see (an admin can grant a manager several teams).
    create_table :team_access do |t|
      t.references :user, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.timestamps
    end
    add_index :team_access, [ :user_id, :team_id ], unique: true
  end
end
