class AddIndexesToContracts < ActiveRecord::Migration[8.0]
  def change
    add_index :contracts, :contracting_entity_id unless index_exists?(:contracts, :contracting_entity_id)
    add_index :contracts, :celebration_date unless index_exists?(:contracts, :celebration_date)
    add_index :contracts, :procedure_type unless index_exists?(:contracts, :procedure_type)
    add_index :contracts, :cpv_code unless index_exists?(:contracts, :cpv_code)
    add_index :contracts, :country_code unless index_exists?(:contracts, :country_code)
  end
end