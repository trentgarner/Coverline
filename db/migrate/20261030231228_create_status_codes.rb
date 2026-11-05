class CreateStatusCodes < ActiveRecord::Migration[8.1]
  def change
    # Many phone-system codes can map to one status (e.g. "AUX-2" and "Break" -> Break).
    create_table :status_codes do |t|
      t.references :status, null: false, foreign_key: true
      t.string :phone_code, null: false
      t.timestamps
    end
    add_index :status_codes, [ :status_id, :phone_code ], unique: true
  end
end
