class AddCountryCodeToEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :country_code, :string, null: false, default: "PT"

    remove_index :entities, :tax_identifier
    add_index :entities, [ :tax_identifier, :country_code ], unique: true,
              name: "index_entities_on_tax_identifier_and_country_code"
  end
end
