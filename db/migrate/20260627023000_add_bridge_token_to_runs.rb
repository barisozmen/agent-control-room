class AddBridgeTokenToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :bridge_token, :string
    add_index :runs, :bridge_token, unique: true

    reversible do |dir|
      dir.up do
        say_with_time "Backfilling run bridge tokens" do
          Run.reset_column_information
          Run.where(bridge_token: nil).find_each do |run|
            run.update_columns(bridge_token: SecureRandom.urlsafe_base64(32))
          end
        end
      end
    end

    change_column_null :runs, :bridge_token, false
  end
end
