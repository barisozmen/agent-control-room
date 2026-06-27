class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.string :runtime_name, null: false
      t.string :project_path, null: false
      t.string :mode, null: false
      t.string :status, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message

      t.timestamps
    end

    add_index :runs, :status
    add_index :runs, [ :runtime_name, :created_at ]
  end
end
