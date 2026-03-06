# frozen_string_literal: true

class AddEntityContractStatsAndIndexes < ActiveRecord::Migration[8.0]
  def up
    # -------------------------------------------------------------------------
    # Pre-computed entity stats — eliminates the expensive GROUP BY + SUM over
    # 2M+ contracts that ran on every entities index page load.
    # -------------------------------------------------------------------------
    add_column :entities, :contract_count, :integer, default: 0, null: false
    add_column :entities, :total_contracted_value, :decimal,
               precision: 15, scale: 2, default: "0.0", null: false

    # Back-fill from existing data in a single SQL pass
    execute <<~SQL
      UPDATE entities
      SET
        contract_count = (
          SELECT COUNT(*) FROM contracts
          WHERE contracts.contracting_entity_id = entities.id
        ),
        total_contracted_value = (
          SELECT COALESCE(SUM(base_price), 0) FROM contracts
          WHERE contracts.contracting_entity_id = entities.id
        )
    SQL

    add_index :entities, :contract_count

    # -------------------------------------------------------------------------
    # Missing contracts indexes used by filter and sort operations
    # -------------------------------------------------------------------------
    unless index_exists?(:contracts, :data_source_id)
      add_index :contracts, :data_source_id
    end
    unless index_exists?(:contracts, :procedure_type)
      add_index :contracts, :procedure_type
    end
    unless index_exists?(:contracts, %i[base_price id], name: "index_contracts_on_base_price_and_id")
      add_index :contracts, %i[base_price id], name: "index_contracts_on_base_price_and_id"
    end
  end

  def down
    remove_column :entities, :contract_count
    remove_column :entities, :total_contracted_value
    remove_index  :contracts, :data_source_id rescue nil
    remove_index  :contracts, :procedure_type rescue nil
    remove_index  :contracts, name: "index_contracts_on_base_price_and_id" rescue nil
  end
end
