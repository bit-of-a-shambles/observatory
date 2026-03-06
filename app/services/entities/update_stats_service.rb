# frozen_string_literal: true

module Entities
  # Refreshes the pre-computed contract_count and total_contracted_value columns
  # on the entities table. Called:
  #   - After every import run (ImportService#call / call_all / call_streaming)
  #   - After every dedup run (dedup rake tasks)
  #   - After the flag scoring cycle (flags:run_all)
  #
  # A single UPDATE … SET … = (SELECT …) is much faster than loading all
  # entities into Ruby and calling #update! on each one.
  class UpdateStatsService
    def call
      ApplicationRecord.connection.execute(<<~SQL)
        UPDATE entities
        SET
          contract_count = (
            SELECT COUNT(*) FROM contracts
            WHERE contracts.contracting_entity_id = entities.id
          ),
          total_contracted_value = (
            SELECT COALESCE(SUM(base_price), 0) FROM contracts
            WHERE contracts.contracting_entity_id = entities.id
          )
      SQL

      true
    end
  end
end
