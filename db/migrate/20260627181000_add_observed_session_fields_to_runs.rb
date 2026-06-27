class AddObservedSessionFieldsToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :runtime_session_id, :string
    add_column :runs, :title, :string
    add_column :runs, :observed_pid, :integer
    add_column :runs, :last_seen_at, :datetime

    add_index :runs, [ :runtime_name, :runtime_session_id ],
      unique: true,
      where: "runtime_session_id IS NOT NULL"
    add_index :runs, [ :last_seen_at, :created_at ]
  end
end
