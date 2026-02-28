# :nocov:
# frozen_string_literal: true

module PortalBase
  class IngestPageJob < ApplicationJob
    class CircuitOpenError < StandardError; end

    queue_as :portal_base_ingestion

    retry_on PublicContracts::PT::PortalBaseClient::TransientError,
             wait: :polynomially_longer,
             attempts: ENV.fetch("PORTAL_BASE_MAX_RETRIES", 5).to_i

    retry_on Net::OpenTimeout, Net::ReadTimeout,
             wait: :polynomially_longer,
             attempts: ENV.fetch("PORTAL_BASE_MAX_RETRIES", 5).to_i

    discard_on ActiveRecord::RecordNotFound

    CIRCUIT_BREAKER_FAILURE_THRESHOLD = ENV.fetch("PORTAL_BASE_CIRCUIT_BREAKER_FAILURE_THRESHOLD", 3).to_i
    CIRCUIT_BREAKER_TTL = 15.minutes

    def perform(data_source_id, page, page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i, run_id: nil)
      data_source = DataSource.find(data_source_id)
      return if stale_run?(data_source, run_id)
      raise CircuitOpenError, "Circuit breaker open for DataSource ##{data_source_id}" if circuit_open?(data_source_id)

      result = PublicContracts::ImportService.new(data_source).call(page: page, page_size: page_size)

      reset_breaker(data_source_id)
      sleep(rate_limit_sleep_seconds) if rate_limit_sleep_seconds.positive?

      return unless result[:fetched] >= page_size

      self.class.perform_later(data_source.id, page + 1, page_size: page_size, run_id: run_id)
    rescue PublicContracts::PT::PortalBaseClient::TransientError, Net::OpenTimeout, Net::ReadTimeout => e
      failures = increment_failure_counter(data_source_id)
      open_breaker!(data_source_id) if failures >= CIRCUIT_BREAKER_FAILURE_THRESHOLD
      Rails.logger.warn({ event: "portal_base.ingest_retry", data_source_id: data_source_id, page: page, failures: failures,
                          error: e.message }.to_json)
      raise
    end

    private

    def stale_run?(data_source, run_id)
      return false if run_id.blank?

      stored_run_id = data_source.config_hash.dig("portal_base_ingestion", "run_id")
      stored_run_id.present? && stored_run_id != run_id
    end

    def rate_limit_sleep_seconds
      ENV.fetch("PORTAL_BASE_PAGE_SLEEP_SECONDS", 0.1).to_f
    end

    def failure_cache_key(data_source_id)
      "portal_base:ingest:failures:#{data_source_id}"
    end

    def open_cache_key(data_source_id)
      "portal_base:ingest:open:#{data_source_id}"
    end

    def increment_failure_counter(data_source_id)
      Rails.cache.increment(failure_cache_key(data_source_id), 1, initial: 0, expires_in: CIRCUIT_BREAKER_TTL)
    end

    def open_breaker!(data_source_id)
      Rails.cache.write(open_cache_key(data_source_id), true, expires_in: CIRCUIT_BREAKER_TTL)
    end

    def circuit_open?(data_source_id)
      Rails.cache.read(open_cache_key(data_source_id)).present?
    end

    def reset_breaker(data_source_id)
      Rails.cache.delete(failure_cache_key(data_source_id))
      Rails.cache.delete(open_cache_key(data_source_id))
    end
  end
end

# :nocov:
