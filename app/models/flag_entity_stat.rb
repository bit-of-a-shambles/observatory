# frozen_string_literal: true

# Pre-aggregated entity exposure, one row per (entity, flag_type, severity).
# Populated by the flags:aggregate rake task — never computed on-demand.
# The dashboard reads from this table instead of joining across 2M+ flags at runtime.
class FlagEntityStat < ApplicationRecord
  belongs_to :entity

  validates :flag_type,     presence: true
  validates :severity,      presence: true
  validates :contract_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :computed_at,   presence: true
end
