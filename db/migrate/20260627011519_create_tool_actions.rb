class CreateToolActions < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_actions do |t|
      t.references :run, null: false, foreign_key: true
      t.references :passport, null: false, foreign_key: true
      t.string :source_event_id
      t.string :capability, null: false
      t.string :action_kind, null: false
      t.text :action_summary
      t.text :command
      t.string :path
      t.json :canonical_payload
      t.string :status, null: false
      t.datetime :requested_at, null: false
      t.datetime :finished_at
      t.integer :exit_status

      t.timestamps
    end

    add_index :tool_actions, [ :run_id, :source_event_id ], unique: true, where: "source_event_id IS NOT NULL"
    add_index :tool_actions, [ :passport_id, :status ]
    add_index :tool_actions, [ :run_id, :requested_at ]
  end
end
