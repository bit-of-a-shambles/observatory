# frozen_string_literal: true

module Flags
  # Populates flag_entity_stats and flag_summary_stats from the flags + contracts
  # tables. Called from flags:aggregate rake task and from tests.
  #
  # This pre-computation is what lets the dashboard respond in milliseconds even
  # when the flags table has millions of rows. Run this after every flag-scoring
  # cycle (i.e. at the end of flags:run_all).
  class AggregateStatsService
    def call
      conn = ActiveRecord::Base.connection
      now  = Time.current.utc.strftime("%Y-%m-%d %H:%M:%S")

      conn.transaction do
        aggregate_entity_stats(conn, now)
        aggregate_summary_stats(conn, now)
      end

      true
    end

    private

    # One row per (entity_id, flag_type, severity) — pre-aggregated from flags JOIN contracts.
    def aggregate_entity_stats(conn, now)
      conn.execute("DELETE FROM flag_entity_stats")
      conn.execute(<<~SQL)
        INSERT INTO flag_entity_stats
          (entity_id, flag_type, severity, total_exposure, contract_count,
           computed_at, created_at, updated_at)
        SELECT
          c.contracting_entity_id        AS entity_id,
          f.flag_type,
          f.severity,
          COALESCE(SUM(c.base_price), 0) AS total_exposure,
          COUNT(*)                        AS contract_count,
          '#{now}', '#{now}', '#{now}'
        FROM flags f
        JOIN contracts c ON c.id = f.contract_id
        GROUP BY c.contracting_entity_id, f.flag_type, f.severity
      SQL
    end

    # One row per severity variant (NULL + high/medium/low) with deduplicated totals.
    def aggregate_summary_stats(conn, now)
      conn.execute("DELETE FROM flag_summary_stats")

      [nil, "high", "medium", "low"].each do |sev|
        sev_where = sev ? "WHERE f.severity = #{conn.quote(sev)}" : ""
        sev_and   = sev ? "AND f.severity = #{conn.quote(sev)}"   : ""
        sev_val   = conn.quote(sev)

        total_exposure = conn.select_value(<<~SQL).to_f
          SELECT COALESCE(SUM(c.base_price), 0)
          FROM contracts c
          WHERE c.id IN (SELECT DISTINCT f.contract_id FROM flags f #{sev_where})
        SQL

        flagged_contracts = conn.select_value(<<~SQL).to_i
          SELECT COUNT(DISTINCT f.contract_id) FROM flags f #{sev_where}
        SQL

        companies = conn.select_value(<<~SQL).to_i
          SELECT COUNT(DISTINCT cw.entity_id)
          FROM flags f
          JOIN contract_winners cw ON cw.contract_id = f.contract_id
          JOIN entities e ON e.id = cw.entity_id
          WHERE e.is_company = 1 #{sev_and}
        SQL

        public_entities = conn.select_value(<<~SQL).to_i
          SELECT COUNT(DISTINCT c.contracting_entity_id)
          FROM flags f
          JOIN contracts c ON c.id = f.contract_id
          JOIN entities e ON e.id = c.contracting_entity_id
          WHERE e.is_public_body = 1 #{sev_and}
        SQL

        conn.execute(<<~SQL)
          INSERT INTO flag_summary_stats
            (severity, total_exposure, flagged_contract_count,
             flagged_companies_count, flagged_public_entities_count,
             computed_at, created_at, updated_at)
          VALUES (
            #{sev_val},
            #{total_exposure},
            #{flagged_contracts},
            #{companies},
            #{public_entities},
            '#{now}', '#{now}', '#{now}'
          )
        SQL
      end
    end
  end
end
