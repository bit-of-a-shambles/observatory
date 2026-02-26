class CreateContractWinners < ActiveRecord::Migration[8.0]
  def change
    create_table :contract_winners do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.decimal :price_share, precision: 15, scale: 2

      t.timestamps
    end
  end
end
