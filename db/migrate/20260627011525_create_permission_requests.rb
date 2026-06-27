class CreatePermissionRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :permission_requests do |t|
      t.references :run, null: false, foreign_key: true
      t.references :passport, null: false, foreign_key: true
      t.references :tool_action, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false
      t.string :risk_level
      t.text :risk_summary
      t.string :suggested_capability
      t.string :suggested_pattern
      t.string :decision
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps
    end

    add_index :permission_requests, [ :run_id, :status ]
    add_index :permission_requests, [ :passport_id, :status ]
  end
end
