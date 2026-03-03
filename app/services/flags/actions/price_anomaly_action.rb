# frozen_string_literal: true

module Flags
  module Actions
    class PriceAnomalyAction
      FLAG_TYPE = "A9_PRICE_ANOMALY"
      SCORE = 30
      SEVERITY = "medium"
      RATIO_MIN = 0.5
      RATIO_MAX = 1.5

      def call
        flagged_rows = anomaly_scope.pluck(:id, :base_price, :total_effective_price)
        upsert_flags(flagged_rows)
        cleanup_stale_flags(flagged_rows.map(&:first))
        flagged_rows.size
      end

      private

      def anomaly_scope
        Contract
          .where.not(base_price: [nil, 0])
          .where.not(total_effective_price: nil)
          .where(
            "CAST(total_effective_price AS FLOAT) / CAST(base_price AS FLOAT) < ? OR " \
            "CAST(total_effective_price AS FLOAT) / CAST(base_price AS FLOAT) > ?",
            RATIO_MIN, RATIO_MAX
          )
      end

      def upsert_flags(flagged_rows)
        return if flagged_rows.empty?

        now = Time.current
        rows = flagged_rows.map do |contract_id, base_price, total_effective_price|
          ratio = (total_effective_price.to_d / base_price.to_d).round(4)
          {
            contract_id: contract_id,
            flag_type: FLAG_TYPE,
            severity: SEVERITY,
            score: SCORE,
            details: {
              "base_price" => base_price.to_s,
              "total_effective_price" => total_effective_price.to_s,
              "ratio" => ratio.to_s,
              "rule" => "A9 price anomaly: ratio outside [#{RATIO_MIN}, #{RATIO_MAX}]"
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
