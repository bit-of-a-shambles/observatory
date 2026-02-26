class CreateContracts < ActiveRecord::Migration[8.0]
  def change
    create_table :contracts do |t|
      t.string :external_id
      t.integer :contracting_entity_id
      t.text :object
      t.string :contract_type
      t.string :procedure_type
      t.date :publication_date
      t.date :celebration_date
      t.decimal :base_price, precision: 15, scale: 2
      t.decimal :total_effective_price, precision: 15, scale: 2
      t.string :cpv_code
      t.string :location

      t.timestamps
    end
    add_index :contracts, :external_id, unique: true
    add_index :contracts, :contracting_entity_id
    add_foreign_key :contracts, :entities, column: :contracting_entity_id
  end
end
