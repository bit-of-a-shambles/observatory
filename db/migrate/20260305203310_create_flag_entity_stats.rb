class CreateFlagEntityStats < ActiveRecord::Migration[8.0]
  def change
    # Pre-aggregated entity exposure — one row per (entity_id, flag_type, severity).
    # Populated by flags:aggregate. Replaces the slow runtime JOIN across 2M+ flags.
    create_table :flag_entity_stats do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :flag_type,      null: false
      t.string  :severity,       null: false
      t.decimal :total_exposure, precision: 15, scale: 2, null: false, default: 0
      t.integer :contract_count, null: false, default: 0
      t.datetime :computed_at,   null: false
      t.timestamps
    end

    add_index :flag_entity_stats, %i[entity_id flag_type severity], unique: true,
              name: "index_flag_entity_stats_unique"
    add_index :flag_entity_stats, %i[severity total_exposure],
              name: "index_flag_entity_stats_sev_exposure"
    add_index :flag_entity_stats, %i[severity contract_count],
              name: "index_flag_entity_stats_sev_count"

    # Pre-computed summary totals — one row per severity (NULL = no filter).
    create_table :flag_summary_stats do |t|
      t.string  :severity                                                           # NULL = all
      t.decimal :total_exposure,               precision: 15, scale: 2, null: false, default: 0
      t.integer :flagged_contract_count,        null: false, default: 0
      t.integer :flagged_companies_count,       null: false, default: 0
      t.integer :flagged_public_entities_count, null: false, default: 0
      t.datetime :computed_at,                  null: false
      t.timestamps
    end

    add_index :flag_summary_stats, :severity, unique: true
  end
end
