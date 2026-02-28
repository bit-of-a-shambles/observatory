# frozen_string_literal: true

require "digest"

module Flags
  class BaseService
    DEFAULT_CONFIDENCE = BigDecimal("0.8")
    DEFAULT_DATA_COMPLETENESS = BigDecimal("1.0")

    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def call(country_code: nil, dry_run: false)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = { evaluated: 0, flagged: 0, created: 0, updated: 0, dry_run: dry_run, country_code: country_code }

      run_scope(country_code:).find_each do |contract|
        result[:evaluated] += 1
        next unless matches?(contract)

        evidence_payload = evidence(contract)
        result[:flagged] += 1

        unless dry_run
          operation = Flag.upsert_for_service!(
            contract_id: contract.id,
            country_code: contract.country_code,
            flag_key: flag_key,
            severity: severity,
            confidence: confidence_for(contract),
            data_completeness: data_completeness_for(contract),
            evidence: evidence_payload,
            fingerprint: fingerprint(contract, evidence_payload),
            detected_at: Time.current
          )
          result[operation] += 1
        end
      end

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      structured_log(result.merge(event: "flags.service.completed", flag_key:, duration_ms: elapsed_ms))
      result.merge(duration_ms: elapsed_ms)
    end

    def description
      raise NotImplementedError, "#{self.class.name} must implement #description"
    end

    def flag_key
      raise NotImplementedError, "#{self.class.name} must implement #flag_key"
    end

    def severity
      raise NotImplementedError, "#{self.class.name} must implement #severity"
    end

    def candidates_scope
      Contract.all
    end

    def matches?(_contract)
      raise NotImplementedError, "#{self.class.name} must implement #matches?"
    end

    def evidence(_contract)
      raise NotImplementedError, "#{self.class.name} must implement #evidence"
    end

    def confidence_for(_contract)
      DEFAULT_CONFIDENCE
    end

    def data_completeness_for(_contract)
      DEFAULT_DATA_COMPLETENESS
    end

    def fingerprint(contract, evidence_payload)
      Digest::SHA256.hexdigest([ contract.id, flag_key, canonicalize(evidence_payload) ].join(":"))
    end

    private

    attr_reader :logger

    def run_scope(country_code:)
      scope = candidates_scope
      return scope if country_code.blank?

      scope.where(country_code: country_code)
    end

    def canonicalize(payload)
      JSON.generate(payload.deep_stringify_keys.sort.to_h)
    end

    def structured_log(payload)
      logger.info(payload.to_json)
    end
  end
end
