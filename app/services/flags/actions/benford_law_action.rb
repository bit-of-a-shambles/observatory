# frozen_string_literal: true

module Flags
  module Actions
    # B5 — Benford's Law deviation
    #
    # In naturally occurring financial data the leading digit d appears with
    # probability P(d) = log10(1 + 1/d).  When a contracting entity's contract
    # amounts deviate significantly from this distribution it may indicate price
    # manipulation, rounding to avoid thresholds, or fabrication.
    #
    # Algorithm:
    #   1. For each entity with ≥ MIN_SAMPLE contracts that have a positive
    #      base_price, extract the leading significant digit (1–9).
    #   2. Compute the chi-square goodness-of-fit statistic (df = 8).
    #   3. Entities whose chi-square exceeds CHI2_P05 (p < 0.05) are flagged;
    #      every qualifying contract of that entity receives a flag.
    #
    # Note: requires sufficient data volume per entity — entities with fewer
    # than MIN_SAMPLE contracts are silently skipped.
    class BenfordLawAction
      FLAG_TYPE  = "B5_BENFORD_DEVIATION"
      MIN_SAMPLE = 20      # minimum contracts for chi-square validity
      CHI2_P05   = 15.507  # critical value at p=0.05, df=8  → medium severity
      CHI2_P01   = 20.090  # critical value at p=0.01, df=8  → high severity
      SCORE_MED  = 35
      SCORE_HIGH = 55

      # Benford expected probability for each leading digit 1–9
      BENFORD = (1..9).each_with_object({}) do |d, h|
        h[d] = Math.log10(1.0 + 1.0 / d)
      end.freeze

      def call
        digit_counts = fetch_digit_counts
        anomalous    = detect_anomalies(digit_counts)
        flagged_rows = fetch_contracts_for_entities(anomalous.keys)
        upsert_flags(flagged_rows, anomalous)
        cleanup_stale_flags(flagged_rows.map(&:first))
        flagged_rows.size
      end

      private

      # Returns { entity_id => { digit => count } } for all entities with base_price ≥ 1
      def fetch_digit_counts
        sql = <<~SQL
          SELECT contracting_entity_id,
                 SUBSTR(CAST(CAST(base_price AS INTEGER) AS TEXT), 1, 1) AS leading_digit,
                 COUNT(*) AS cnt
          FROM   contracts
          WHERE  base_price >= 1
            AND  contracting_entity_id IS NOT NULL
          GROUP  BY contracting_entity_id, leading_digit
          HAVING leading_digit BETWEEN '1' AND '9'
        SQL

        counts = Hash.new { |h, k| h[k] = Hash.new(0) }
        ApplicationRecord.connection.select_all(sql).each do |row|
          entity_id = row["contracting_entity_id"]
          digit     = row["leading_digit"].to_i
          cnt       = row["cnt"].to_i
          counts[entity_id][digit] += cnt
        end
        counts
      end

      # Returns { entity_id => { chi2:, n:, observed:, severity: } } for entities that deviate
      def detect_anomalies(digit_counts)
        anomalous = {}

        digit_counts.each do |entity_id, by_digit|
          n = by_digit.values.sum
          next if n < MIN_SAMPLE

          chi2 = (1..9).sum do |d|
            observed = by_digit[d].to_f
            expected = BENFORD[d] * n
            (observed - expected)**2 / expected
          end.round(4)

          next if chi2 < CHI2_P05

          anomalous[entity_id] = {
            chi2:     chi2,
            n:        n,
            observed: (1..9).each_with_object({}) { |d, h| h[d.to_s] = by_digit[d] },
            severity: chi2 >= CHI2_P01 ? "high" : "medium"
          }
        end

        anomalous
      end

      def fetch_contracts_for_entities(entity_ids)
        return [] if entity_ids.empty?

        Contract
          .where(contracting_entity_id: entity_ids)
          .where("base_price >= 1")
          .pluck(:id, :contracting_entity_id, :base_price)
      end

      def upsert_flags(flagged_rows, anomalous)
        return if flagged_rows.empty?

        now  = Time.current
        rows = flagged_rows.map do |contract_id, entity_id, base_price|
          stats = anomalous[entity_id]
          score = stats[:chi2] >= CHI2_P01 ? SCORE_HIGH : SCORE_MED

          {
            contract_id: contract_id,
            flag_type:   FLAG_TYPE,
            severity:    stats[:severity],
            score:       score,
            details: {
              "chi2"                => stats[:chi2].to_s,
              "sample_size"         => stats[:n].to_s,
              "contract_base_price" => base_price.to_s,
              "observed"            => stats[:observed],
              "rule"                => "B5 Benford's Law deviation: chi-square #{stats[:chi2]} " \
                                       "(df=8, n=#{stats[:n]}, threshold=#{CHI2_P05})"
            },
            fired_at:   now,
            created_at: now,
            updated_at: now
          }
        end

        Flag.upsert_all(rows, unique_by: :index_flags_on_contract_id_and_flag_type)
      end

      def cleanup_stale_flags(flagged_contract_ids)
        stale_scope = Flag.where(flag_type: FLAG_TYPE)
        if flagged_contract_ids.empty?
          stale_scope.delete_all
        else
          stale_scope.where.not(contract_id: flagged_contract_ids).delete_all
        end
      end
    end
  end
end
