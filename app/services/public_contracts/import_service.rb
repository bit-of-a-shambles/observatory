# :nocov:
# frozen_string_literal: true

require "set"

module PublicContracts
  class ImportService
    DEFAULT_PAGE_SIZE = 50
    IMPORTABLE_CONTRACT_COLUMNS = %w[
      external_id
      country_code
      object
      contract_type
      procedure_type
      publication_date
      celebration_date
      base_price
      total_effective_price
      cpv_code
      location
      contracting_entity_id
      data_source_id
      created_at
      updated_at
    ].freeze
    UPSERT_UPDATE_COLUMNS = (IMPORTABLE_CONTRACT_COLUMNS - %w[external_id country_code created_at]).freeze

    def initialize(data_source_record, logger: Rails.logger)
      @ds = data_source_record
      @logger = logger
    end

    def call(page: 1, page_size: DEFAULT_PAGE_SIZE, full: false)
      return import_full(page_size: page_size) if full

      import_page(page: page, page_size: page_size)
    rescue StandardError
      @ds.update!(status: :error)
      raise
    end

    private

    def import_full(page_size:)
      current_page = 1
      totals = empty_result.merge(start_page: current_page)

      loop do
        page_result = import_page(page: current_page, page_size: page_size)
        merge!(totals, page_result)
        break if page_result[:fetched].zero?

        current_page += 1
      end

      totals
    end

    def import_page(page:, page_size:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      payload = Array(@ds.adapter.fetch_contracts(page: page, limit: page_size))
      result = empty_result.merge(page: page, page_size: page_size, fetched: payload.size)

      normalized_contracts = build_contract_rows(payload, result)
      upsert_contract_rows(normalized_contracts, result)
      sync_winners(normalized_contracts, payload)

      @ds.update!(
        status: :active,
        last_synced_at: Time.current,
        record_count: Contract.where(data_source_id: @ds.id).count,
        last_success_page: [ @ds.last_success_page.to_i, page.to_i ].max
      )

      structured_log(
        event: "portal_base.page_imported",
        data_source_id: @ds.id,
        page: page,
        page_size: page_size,
        fetched: result[:fetched],
        inserted: result[:inserted],
        updated: result[:updated],
        failed: result[:failed],
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      )

      result
    end

    def build_contract_rows(payload, result)
      now = Time.current

      payload.filter_map do |attrs|
        row = build_contract_row(attrs, now: now)
        if row.nil?
          result[:failed] += 1
          structured_log(event: "portal_base.contract_failed", external_id: attrs["external_id"], error: "invalid payload")
        end
        row
      rescue StandardError => e
        result[:failed] += 1
        structured_log(event: "portal_base.contract_failed", external_id: attrs["external_id"], error: e.message)
        nil
      end
    end

    def build_contract_row(attrs, now:)
      country_code = attrs["country_code"].presence || @ds.country_code
      external_id = attrs["external_id"].presence
      return nil if external_id.blank? || country_code.blank?

      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return nil unless contracting

      {
        "external_id" => external_id,
        "country_code" => country_code,
        "object" => attrs["object"],
        "contract_type" => attrs["contract_type"],
        "procedure_type" => attrs["procedure_type"],
        "publication_date" => attrs["publication_date"],
        "celebration_date" => attrs["celebration_date"],
        "base_price" => attrs["base_price"],
        "total_effective_price" => attrs["total_effective_price"],
        "cpv_code" => attrs["cpv_code"],
        "location" => attrs["location"],
        "contracting_entity_id" => contracting.id,
        "data_source_id" => @ds.id,
        "created_at" => now,
        "updated_at" => now
      }
    end

    def upsert_contract_rows(rows, result)
      return if rows.empty?

      existing_keys = existing_contract_keys(rows)
      rows.each do |row|
        key = [ row["external_id"], row["country_code"] ]
        existing_keys.include?(key) ? result[:updated] += 1 : result[:inserted] += 1
      end

      Contract.upsert_all(
        rows,
        unique_by: :index_contracts_on_external_id_and_country_code,
        update_only: UPSERT_UPDATE_COLUMNS
      )
    end

    def existing_contract_keys(rows)
      external_ids = rows.map { |row| row["external_id"] }.uniq
      country_codes = rows.map { |row| row["country_code"] }.uniq

      Contract.where(external_id: external_ids, country_code: country_codes)
              .pluck(:external_id, :country_code)
              .to_set
    end

    def sync_winners(rows, payload)
      return if rows.empty?

      payload_by_key = payload.index_by { |attrs| [ attrs["external_id"], attrs["country_code"].presence || @ds.country_code ] }
      contract_by_key = Contract.where(external_id: rows.map { |row| row["external_id"] },
                                       country_code: rows.map { |row| row["country_code"] })
                                .index_by { |contract| [ contract.external_id, contract.country_code ] }

      contract_by_key.each do |key, contract|
        winner_rows(payload_by_key[key]).each do |winner|
          ContractWinner.find_or_create_by!(contract_id: contract.id, entity_id: winner.id)
        end
      end
    end

    def winner_rows(attrs)
      return [] if attrs.nil?

      Array(attrs["winners"]).filter_map do |winner_attrs|
        find_or_create_entity(
          winner_attrs["tax_identifier"],
          winner_attrs["name"],
          is_company: winner_attrs["is_company"] || false
        )
      rescue StandardError => e
        structured_log(event: "portal_base.winner_failed", external_id: attrs["external_id"], error: e.message)
        nil
      end
    end

    def find_or_create_entity(tax_id, name, is_public_body: false, is_company: false)
      return nil if tax_id.blank? || name.blank?

      entity = Entity.find_or_initialize_by(tax_identifier: tax_id, country_code: @ds.country_code)
      entity.assign_attributes(name: name, is_public_body: is_public_body, is_company: is_company)
      entity.save!
      entity
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def empty_result
      { fetched: 0, inserted: 0, updated: 0, failed: 0 }
    end

    def merge!(totals, page_result)
      totals[:fetched] += page_result[:fetched]
      totals[:inserted] += page_result[:inserted]
      totals[:updated] += page_result[:updated]
      totals[:failed] += page_result[:failed]
    end

    def structured_log(payload)
      @logger.info(payload.to_json)
    end
  end
end

# :nocov:
