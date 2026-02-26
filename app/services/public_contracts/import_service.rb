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
      contract = Contract.find_or_initialize_by(
        external_id:  attrs["external_id"],
        country_code: attrs["country_code"] || @ds.country_code
      )
      if cross_source_collision?(contract)
        log_cross_source_collision(contract)
        return
      end

      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return unless contracting

      contract_attrs = {
        object:                attrs["object"].presence,
        country_code:          attrs["country_code"] || @ds.country_code,
        contract_type:         attrs["contract_type"].presence,
        procedure_type:        attrs["procedure_type"].presence,
        publication_date:      attrs["publication_date"],
        celebration_date:      attrs["celebration_date"],
        base_price:            attrs["base_price"],
        total_effective_price: attrs["total_effective_price"],
        cpv_code:              attrs["cpv_code"].presence,
        location:              attrs["location"].presence
      }.compact

      contract.assign_attributes(
        contract_attrs.merge(
          contracting_entity: contracting,
          data_source: @ds
        )
      )
      contract.save! if contract.new_record? || contract.changed?

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

    def cross_source_collision?(contract)
      contract.persisted? &&
        contract.data_source_id.present? &&
        contract.data_source_id != @ds.id
    end

    def log_cross_source_collision(contract)
      Rails.logger.warn(
        "[ImportService] Skipping contract due to cross-source collision " \
        "external_id=#{contract.external_id} country_code=#{contract.country_code} " \
        "existing_data_source_id=#{contract.data_source_id} incoming_data_source_id=#{@ds.id}"
      )
    end
  end
end
