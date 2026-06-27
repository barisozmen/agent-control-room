class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :run, null: false, foreign_key: true
      t.references :passport, null: true, foreign_key: true
      t.references :tool_action, null: true, foreign_key: true
      t.references :permission_request, null: true, foreign_key: true
      t.string :source_event_id
      t.string :event_kind, null: false
      t.string :actor_lineage
      t.string :capability
      t.text :action_summary
      t.string :decision
      t.string :result, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :audit_events, [ :run_id, :occurred_at ]
    add_index :audit_events, [ :passport_id, :occurred_at ]
    add_index :audit_events, [ :run_id, :source_event_id ], unique: true, where: "source_event_id IS NOT NULL"
  end
end
