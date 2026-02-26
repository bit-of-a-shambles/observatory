class AddCountryCodeScopeToContractsExternalId < ActiveRecord::Migration[8.0]
  def change
    remove_index :contracts, :external_id
    add_index :contracts, [:external_id, :country_code], unique: true,
              name: "index_contracts_on_external_id_and_country_code"
  end
end
