class CreateUnmatchedEvents < ActiveRecord::Migration[8.1]
  def change
    # Phone events we couldn't fully place, kept so an admin can fix the mapping:
    #   unknown_agent  - no agent has that phone ID yet (event is held, not recorded)
    #   unmapped_code  - the code maps to no status (event IS recorded, as "Unmapped")
    create_table :unmatched_events do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :reason, null: false
      t.string :phone_agent_id
      t.string :phone_code
      t.datetime :occurred_at
      t.string :external_event_id
      t.jsonb :payload, null: false, default: {}
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :unmatched_events, [ :organization_id, :reason, :resolved_at ]
    add_index :unmatched_events, [ :organization_id, :reason, :external_event_id ], unique: true,
              where: "external_event_id IS NOT NULL", name: "index_unmatched_events_once_per_event"
  end
end
