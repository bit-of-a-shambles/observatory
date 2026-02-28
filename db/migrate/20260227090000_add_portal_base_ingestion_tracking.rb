class AddPortalBaseIngestionTracking < ActiveRecord::Migration[8.0]
  def change
    add_column :data_sources, :last_success_page, :integer, null: false, default: 0

    add_index :contract_winners,
              [ :contract_id, :entity_id ],
              unique: true,
              name: "index_contract_winners_on_contract_and_entity"
  end
end
