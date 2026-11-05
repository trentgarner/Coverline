class CreateStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :statuses do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6c757d"
      # ready | on_call | wrap_up | break | lunch | meeting | offline | other
      t.string :category, null: false
      t.boolean :productive, null: false, default: false
      t.boolean :counts_toward_cft, null: false, default: false
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true
      # Past this many minutes in the status the board flags it (e.g. a break over 15). Optional.
      t.integer :time_limit_minutes
      t.timestamps
    end
    add_index :statuses, [ :organization_id, :name ], unique: true
  end
end
