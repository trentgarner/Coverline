class CreateStatusEvents < ActiveRecord::Migration[8.1]
  def change
    # One row per status change. ended_at NULL means "this is the current status".
    create_table :status_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :status, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :source, null: false # phone | manual | simulator
      t.string :external_event_id   # the phone system's id for this event; makes retries harmless
      t.timestamps
    end
    add_index :status_events, [ :user_id, :started_at ]
    add_index :status_events, :external_event_id, unique: true
    # Fast "current status" lookup, and a hard guarantee of one open event per agent.
    add_index :status_events, :user_id, unique: true, where: "ended_at IS NULL", name: "index_status_events_one_open_per_user"
    add_check_constraint :status_events, "ended_at IS NULL OR ended_at >= started_at", name: "status_events_ended_after_started"
  end
end
