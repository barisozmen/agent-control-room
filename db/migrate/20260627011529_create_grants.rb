class CreateGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :grants do |t|
      t.references :passport, null: false, foreign_key: true
      t.references :permission_request, null: true, foreign_key: true
      t.string :capability, null: false
      t.string :pattern, null: false
      t.string :effect, null: false
      t.string :scope, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :grants, [ :passport_id, :capability, :pattern, :effect ], unique: true
  end
end
