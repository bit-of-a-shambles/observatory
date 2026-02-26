class CreateDataSources < ActiveRecord::Migration[8.0]
  def change
    create_table :data_sources do |t|
      t.string  :country_code,  null: false
      t.string  :name,          null: false
      t.string  :source_type,   null: false
      t.string  :adapter_class, null: false
      t.text    :config
      t.string  :status,        null: false, default: "inactive"
      t.datetime :last_synced_at
      t.integer :record_count,  default: 0

      t.timestamps
    end

    add_index :data_sources, :country_code
    add_index :data_sources, :status
  end
end
