class UpgradeFlagsFoundationSchema < ActiveRecord::Migration[8.0]
  def up
    add_column :flags, :country_code, :string unless column_exists?(:flags, :country_code)
    add_column :flags, :flag_key, :string unless column_exists?(:flags, :flag_key)
    add_column :flags, :confidence, :decimal, precision: 5, scale: 4 unless column_exists?(:flags, :confidence)
    add_column :flags, :data_completeness, :decimal, precision: 5, scale: 4 unless column_exists?(:flags, :data_completeness)
    add_column :flags, :evidence, :json, default: {} unless column_exists?(:flags, :evidence)
    add_column :flags, :fingerprint, :string unless column_exists?(:flags, :fingerprint)
    add_column :flags, :detected_at, :datetime unless column_exists?(:flags, :detected_at)

    add_index :flags, :country_code unless index_exists?(:flags, :country_code)
    add_index :flags, [ :contract_id, :flag_key ], unique: true, name: :index_flags_on_contract_id_and_flag_key unless index_exists?(:flags, [ :contract_id, :flag_key ], unique: true, name: :index_flags_on_contract_id_and_flag_key)
    add_index :flags, :flag_key unless index_exists?(:flags, :flag_key)

    change_column_null :flags, :flag_type, true
    change_column_null :flags, :score, true
    change_column_null :flags, :fired_at, true

    execute <<~SQL
      UPDATE flags
      SET flag_key = flag_type
      WHERE flag_key IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET confidence = 0.8000
      WHERE confidence IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET data_completeness = 1.0000
      WHERE data_completeness IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET evidence = details
      WHERE evidence IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET detected_at = fired_at
      WHERE detected_at IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET country_code = (
        SELECT contracts.country_code
        FROM contracts
        WHERE contracts.id = flags.contract_id
      )
      WHERE country_code IS NULL
    SQL

    execute <<~SQL
      UPDATE flags
      SET fingerprint = 'legacy-' || id
      WHERE fingerprint IS NULL OR fingerprint = ''
    SQL
  end

  def down
    remove_index :flags, name: :index_flags_on_contract_id_and_flag_key if index_exists?(:flags, [ :contract_id, :flag_key ], unique: true, name: :index_flags_on_contract_id_and_flag_key)
    remove_index :flags, :flag_key if index_exists?(:flags, :flag_key)
    remove_index :flags, :country_code if index_exists?(:flags, :country_code)

    remove_column :flags, :detected_at if column_exists?(:flags, :detected_at)
    remove_column :flags, :fingerprint if column_exists?(:flags, :fingerprint)
    remove_column :flags, :evidence if column_exists?(:flags, :evidence)
    remove_column :flags, :data_completeness if column_exists?(:flags, :data_completeness)
    remove_column :flags, :confidence if column_exists?(:flags, :confidence)
    remove_column :flags, :flag_key if column_exists?(:flags, :flag_key)
    remove_column :flags, :country_code if column_exists?(:flags, :country_code)

    change_column_null :flags, :flag_type, false
    change_column_null :flags, :score, false
    change_column_null :flags, :fired_at, false
  end
end
