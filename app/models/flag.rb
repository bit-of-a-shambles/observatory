class Flag < ApplicationRecord
  belongs_to :contract

  enum :severity, {
    low: "low",
    medium: "medium",
    high: "high",
    critical: "critical"
  }, default: "medium"

  validates :flag_type, presence: true, uniqueness: { scope: :contract_id }
  validates :severity, presence: true
  validates :score, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :fired_at, presence: true
end
