class CreateFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :flags do |t|
      t.references :contract, null: false, foreign_key: true
      t.string :flag_type, null: false
      t.string :severity, null: false
      t.integer :score, null: false
      t.json :details, default: {}
      t.datetime :fired_at, null: false

      t.timestamps
    end

    add_index :flags, [ :contract_id, :flag_type ], unique: true
    add_index :flags, :flag_type
    add_index :flags, :severity
  end
end
