# frozen_string_literal: true

module Flags
  module Actions
    class DateSequenceAnomalyAction
      FLAG_TYPE = "A2_PUBLICATION_AFTER_CELEBRATION"
      SCORE = 40
      SEVERITY = "high"

      def call
        flagged_rows = anomaly_scope.pluck(:id, :publication_date, :celebration_date)
        upsert_flags(flagged_rows)
        cleanup_stale_flags(flagged_rows.map(&:first))
        flagged_rows.size
      end

      private

      def anomaly_scope
        Contract.where.not(publication_date: nil, celebration_date: nil)
                .where("celebration_date < publication_date")
      end

      def upsert_flags(flagged_rows)
        return if flagged_rows.empty?

        now = Time.current
        rows = flagged_rows.map do |contract_id, publication_date, celebration_date|
          {
            contract_id: contract_id,
            flag_type: FLAG_TYPE,
            severity: SEVERITY,
            score: SCORE,
            details: {
              "publication_date" => publication_date.iso8601,
              "celebration_date" => celebration_date.iso8601,
              "rule" => "A2/A3 date sequence anomaly"
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
