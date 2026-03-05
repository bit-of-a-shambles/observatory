# frozen_string_literal: true

# Pre-computed aggregate totals for the dashboard sidebar.
# One row per severity level (NULL = no filter, "high"/"medium"/"low" for filtered).
# Populated by the flags:aggregate rake task.
class FlagSummaryStat < ApplicationRecord
  validates :computed_at, presence: true
  validates :flagged_contract_count,        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :flagged_companies_count,       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :flagged_public_entities_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
