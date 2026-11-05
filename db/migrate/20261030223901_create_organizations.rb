class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :timezone, null: false, default: "America/Chicago"
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
  end
end
