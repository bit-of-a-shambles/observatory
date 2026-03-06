class AddEntitySortIndexesToContracts < ActiveRecord::Migration[8.0]
  # The entity show page sorts up to 23k+ contracts for a single entity.
  # Without compound indexes SQLite does "USE TEMP B-TREE FOR ORDER BY" —
  # loading every matched row into memory before returning page 1 of 50.
  #
  # Adding (contracting_entity_id, <sort_col>, id) lets SQLite satisfy
  # both the WHERE contracting_entity_id = ? and the ORDER BY in one
  # index scan, returning the first 50 rows without sorting the full set.
  # Each index supports both ASC and DESC traversal (SQLite can scan
  # forward or backward).
  def change
    add_index :contracts, %i[contracting_entity_id celebration_date id],
              name: "idx_contracts_entity_celebration_id"

    add_index :contracts, %i[contracting_entity_id base_price id],
              name: "idx_contracts_entity_base_price_id"

    add_index :contracts, %i[contracting_entity_id object id],
              name: "idx_contracts_entity_object_id"

    # Covers the publication_date range filter combined with default sort.
    add_index :contracts, %i[contracting_entity_id publication_date id],
              name: "idx_contracts_entity_publication_date_id"
  end
end
