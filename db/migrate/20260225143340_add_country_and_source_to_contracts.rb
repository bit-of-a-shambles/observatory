class AddCountryAndSourceToContracts < ActiveRecord::Migration[8.0]
  def change
    add_column :contracts, :country_code, :string, null: false, default: "PT"
    add_reference :contracts, :data_source, null: true, foreign_key: true
  end
end
