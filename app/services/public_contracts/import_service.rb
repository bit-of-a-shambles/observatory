# frozen_string_literal: true

module PublicContracts
  class ImportService
    def initialize(data_source_record)
      @ds = data_source_record
    end

    def call
      contracts = @ds.adapter.fetch_contracts
      contracts.each { |attrs| import_contract(attrs) }
      @ds.update!(status: :active, last_synced_at: Time.current, record_count: contracts.size)
    rescue => e
      @ds.update!(status: :error)
      raise
    end

    private

    def import_contract(attrs)
      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return unless contracting

      contract = Contract.find_or_create_by!(
        external_id: attrs["external_id"]
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
