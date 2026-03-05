# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Used in dashboard WHERE/JOIN filters — was doing full scans
    add_index :entities, :is_public_body, if_not_exists: true
    add_index :entities, :is_company,     if_not_exists: true

    # Used in flags:run_all scans and dashboard aggregates
    add_index :contracts, :base_price,           if_not_exists: true
    add_index :contracts, :publication_date,     if_not_exists: true
    add_index :contracts, :total_effective_price, if_not_exists: true
  end
end
