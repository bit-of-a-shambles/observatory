# frozen_string_literal: true

module Flags
  module Actions
    class ThresholdSplittingAction
      FLAG_TYPE = "A5_THRESHOLD_SPLITTING"
      SCORE     = 35
      SEVERITY  = "medium"
      WINDOW    = 0.05 # 5% below threshold

      THRESHOLDS = [
        5_000,
        20_000,
        75_000,
        150_000,
        5_350_000
      ].map(&:to_d).freeze

      def call
        flagged_rows = anomaly_scope.pluck(:id, :base_price)
        upsert_flags(flagged_rows)
        cleanup_stale_flags(flagged_rows.map(&:first))
        flagged_rows.size
      end

      private

      def anomaly_scope
        conditions = THRESHOLDS.map do |t|
          lower = t * (1 - WINDOW)
          "base_price >= #{lower} AND base_price < #{t}"
        end.join(" OR ")

        Contract.where.not(base_price: nil).where(conditions)
      end

      def nearest_threshold(base_price)
        price = base_price.to_d
        THRESHOLDS.find { |t| price >= t * (1 - WINDOW) && price < t }
      end

      def upsert_flags(flagged_rows)
        return if flagged_rows.empty?

        now = Time.current
        rows = flagged_rows.map do |contract_id, base_price|
          threshold = nearest_threshold(base_price)
          {
            contract_id: contract_id,
            flag_type: FLAG_TYPE,
            severity: SEVERITY,
            score: SCORE,
            details: {
              "base_price" => base_price.to_s,
              "threshold"  => threshold.to_s,
              "rule"       => "A5 threshold splitting: price within 5% below #{threshold}"
            },
            fired_at: now,
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
