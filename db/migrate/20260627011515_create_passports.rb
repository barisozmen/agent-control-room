class CreatePassports < ActiveRecord::Migration[8.1]
  def change
    create_table :passports do |t|
      t.references :run, null: false, foreign_key: true
      t.references :parent, null: true, foreign_key: { to_table: :passports }
      t.string :actor_ref, null: false
      t.string :actor_name, null: false
      t.string :actor_kind, null: false
      t.string :provider, null: false
      t.text :task
      t.string :read_rule, null: false
      t.string :edit_rule, null: false
      t.string :bash_rule, null: false
      t.string :web_rule, null: false
      t.string :delegate_rule, null: false
      t.string :status, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :passports, [ :run_id, :actor_ref ], unique: true
    add_index :passports, [ :run_id, :status ]
  end
end
