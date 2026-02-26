class CreateEntities < ActiveRecord::Migration[8.0]
  def change
    create_table :entities do |t|
      t.string :name
      t.string :tax_identifier
      t.boolean :is_public_body
      t.boolean :is_company
      t.string :address
      t.string :postal_code
      t.string :locality

      t.timestamps
    end
    add_index :entities, :tax_identifier
  end
end
