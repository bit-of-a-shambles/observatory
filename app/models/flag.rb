require "digest"

class Flag < ApplicationRecord
  SEVERITIES = %w[low medium high].freeze
  DEFAULT_CONFIDENCE = BigDecimal("0.8")
  DEFAULT_DATA_COMPLETENESS = BigDecimal("1.0")
  LEGACY_SCORE_BY_SEVERITY = {
    "low" => 20,
    "medium" => 40,
    "high" => 70
  }.freeze

  belongs_to :contract

  validates :contract_id, :country_code, :flag_key, :severity, :fingerprint, :detected_at, presence: true
  validates :flag_key, uniqueness: { scope: :contract_id }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :confidence, :data_completeness,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :country_code,
            format: {
              with: /\A[A-Z]{2}\z/,
              message: "must be a 2-letter ISO 3166-1 alpha-2 code (e.g. PT, ES)"
            }

  before_validation :sync_modern_fields_from_legacy
  before_validation :sync_country_code_from_contract
  before_validation :default_detected_at
  before_validation :default_confidence_fields
  before_validation :default_fingerprint
  before_validation :sync_legacy_fields

  validate :contract_country_code_must_match

  def self.upsert_for_service!(attributes)
    contract_id = attributes.fetch(:contract_id)
    flag_key = attributes.fetch(:flag_key)

    record = find_or_initialize_by(contract_id:, flag_key:)
    created = record.new_record?
    record.assign_attributes(attributes)
    record.save!

    created ? :created : :updated
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  private

  def sync_modern_fields_from_legacy
    self.flag_key ||= flag_type
    self.detected_at ||= fired_at
    self.evidence = details if evidence.blank? && details.present?
  end

  def sync_country_code_from_contract
    self.country_code = contract&.country_code if contract_id.present?
  end

  def default_detected_at
    self.detected_at ||= Time.current
  end

  def default_confidence_fields
    self.confidence ||= DEFAULT_CONFIDENCE
    self.data_completeness ||= DEFAULT_DATA_COMPLETENESS
  end

  def default_fingerprint
    return if fingerprint.present? || contract_id.blank? || flag_key.blank?

    self.fingerprint = Digest::SHA256.hexdigest([ contract_id, flag_key, detected_at.to_i ].join(":"))
  end

  def sync_legacy_fields
    self.flag_type = flag_key if flag_key.present?
    self.fired_at = detected_at if detected_at.present?
    self.details = evidence if evidence.present?
    self.score ||= LEGACY_SCORE_BY_SEVERITY.fetch(severity, 0) if severity.present?
  end

  def contract_country_code_must_match
    return if contract.nil? || country_code.blank?
    return if contract.country_code == country_code

    errors.add(:country_code, "must match the associated contract country")
  end
end
