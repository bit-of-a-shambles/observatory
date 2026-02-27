# frozen_string_literal: true

module PublicContracts
  class ImportService
    def initialize(data_source_record)
      @ds = data_source_record
    end

    def call
      contracts = adapter.fetch_contracts
      contracts.each { |attrs| import_contract(attrs) }
      @ds.update!(status: :active, last_synced_at: Time.current, record_count: contracts.size)
    rescue => e
      @ds.update!(status: :error)
      raise
    end

    # Paginates through every page until the adapter returns no more records.
    # The adapter must support fetch_contracts(page:, limit:).
    # Optional: if the adapter responds to #total_count, it's used only for
    # progress reporting — not to control the loop.
    #
    # The adapter is memoized for the lifetime of this call so that stateful
    # adapters (e.g. TedClient scroll token, SnsClient year-window index) retain
    # their internal position across batches.
    def call_all(limit: 100, progress: $stdout)
      total_known  = adapter.respond_to?(:total_count) ? adapter.total_count : nil
      imported     = 0
      page         = 1

      loop do
        batch = adapter.fetch_contracts(page: page, limit: limit)
        break if batch.empty?

        batch.each { |attrs| import_contract(attrs) }
        imported += batch.size
        page     += 1

        # Pace requests for rate-limited adapters (e.g. TED API)
        sleep adapter.inter_page_delay if adapter.respond_to?(:inter_page_delay)

        if progress && total_known
          progress.print "\r  #{imported}/#{total_known} imported (page #{page - 1})"
          progress.flush
        end
      end

      progress&.puts "\n  Done — #{imported} records"
      @ds.update!(status: :active, last_synced_at: Time.current, record_count: imported)
    rescue => e
      @ds.update!(status: :error)
      raise
    end

    private

    # Memoized adapter — critical for stateful adapters (TedClient scroll token,
    # SnsClient year-window index) that need the same instance across all batches.
    def adapter
      @adapter ||= @ds.adapter
    end

    # Dedup strategy: the DB unique constraint on (external_id, country_code)
    # prevents duplicate contracts both within a single source (on re-import) and
    # across sources that share the same external_id namespace (e.g. Portal BASE and
    # QuemFatura.pt both use idcontrato). find_or_create_by! returns the existing
    # record silently when a duplicate is encountered — no error, no overwrite.
    def import_contract(attrs)
      return if attrs["object"].blank?

      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return unless contracting

      contract = Contract.find_or_create_by!(
        external_id:  attrs["external_id"],
        country_code: attrs["country_code"] || @ds.country_code
      ) do |c|
        c.object               = attrs["object"]
        c.country_code         = attrs["country_code"] || @ds.country_code
        c.contract_type        = attrs["contract_type"]
        c.procedure_type       = attrs["procedure_type"]
        c.publication_date     = attrs["publication_date"]
        c.celebration_date     = attrs["celebration_date"]
        c.base_price           = attrs["base_price"]
        c.total_effective_price = attrs["total_effective_price"]
        c.cpv_code             = attrs["cpv_code"]
        c.location             = attrs["location"]
        c.contracting_entity   = contracting
        c.data_source          = @ds
      end

      Array(attrs["winners"]).each do |winner_attrs|
        winner = find_or_create_entity(
          winner_attrs["tax_identifier"],
          winner_attrs["name"],
          is_company: winner_attrs["is_company"] || false
        )
        next unless winner
        ContractWinner.find_or_create_by!(contract: contract, entity: winner)
      end
    end

    def find_or_create_entity(tax_id, name, is_public_body: false, is_company: false)
      return nil if tax_id.blank? || name.blank?

      Entity.find_or_create_by!(tax_identifier: tax_id, country_code: @ds.country_code) do |e|
        e.name          = name
        e.is_public_body = is_public_body
        e.is_company    = is_company
      end
    end
  end
end
