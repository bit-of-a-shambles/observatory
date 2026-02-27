class DashboardController < ApplicationController
  include ActionView::Helpers::NumberHelper

  def index
    flagged_contract_ids = Flag.distinct.pluck(:contract_id)
    flagged_contracts_scope = Contract.where(id: flagged_contract_ids)
    flags_count = Flag.count
    @flag_types = Flag.distinct.order(:flag_type).pluck(:flag_type)
    @insights_count = flags_count
    @entity_sort = params[:entity_sort] == "count" ? "count" : "value"
    @entity_flag_type = params[:entity_flag_type].presence
    @entity_exposure_rows = entity_exposure_rows(sort_by: @entity_sort, flag_type: @entity_flag_type)

    @stats = [
      { label: t("stats.contracts"), value: number_with_delimiter(Contract.count),              color: "text-[#c8a84e]" },
      { label: t("stats.entities"),  value: number_with_delimiter(Entity.count),                color: "text-[#e8e0d4]" },
      { label: t("stats.sources"),   value: DataSource.where(status: :active).count.to_s,       color: "text-[#e8e0d4]" },
      { label: t("stats.alerts"),    value: number_with_delimiter(flags_count),                 color: "text-[#ff4444]" }
    ]

    source_contract_counts = Contract.where.not(data_source_id: nil).group(:data_source_id).count

    @sources = DataSource.order(:country_code, :name).map do |ds|
      {
        name:       ds.name,
        country:    ds.country_code,
        type:       ds.source_type.capitalize,
        status:     ds.status,
        records:    number_with_delimiter(source_contract_counts.fetch(ds.id, 0)),
        synced_at:  ds.last_synced_at&.strftime("%Y-%m-%d %H:%M")
      }
    end

    @flagged_total_exposure = flagged_contracts_scope.sum(:base_price)
    @flagged_contract_count = flagged_contract_ids.size
    @flagged_companies_count = Entity.joins(:contract_winners)
                                     .where(contract_winners: { contract_id: flagged_contract_ids })
                                     .where(is_company: true)
                                     .distinct
                                     .count
    @flagged_public_entities_count = flagged_contracts_scope.joins(:contracting_entity)
                                                           .where(entities: { is_public_body: true })
                                                           .distinct
                                                           .count(:contracting_entity_id)

    @crossings = [
      { label: t("dashboard.crossings.contracts_with_winners"), count: number_with_delimiter(Entity.where(is_public_body: false).count) },
      { label: t("dashboard.crossings.public_bodies"),          count: number_with_delimiter(Entity.where(is_public_body: true).count) },
      { label: t("dashboard.crossings.ecfp_donors"),            count: "—" },
      { label: t("dashboard.crossings.tdc_sanctions"),          count: "—" }
    ]
  end

  private

  def entity_exposure_rows(sort_by:, flag_type:)
    scope = Flag.joins(contract: :contracting_entity)
    scope = scope.where(flag_type: flag_type) if flag_type.present?

    order_sql = if sort_by == "count"
      "exposure_count DESC, exposure_value DESC, entities.name ASC"
    else
      "exposure_value DESC, exposure_count DESC, entities.name ASC"
    end

    scope.select(
      "flags.flag_type AS flag_type",
      "contracts.contracting_entity_id AS entity_id",
      "entities.name AS entity_name",
      "COALESCE(SUM(COALESCE(contracts.base_price, 0)), 0) AS exposure_value",
      "COUNT(DISTINCT contracts.id) AS exposure_count"
    ).group(
      "flags.flag_type, contracts.contracting_entity_id, entities.name"
    ).order(
      Arel.sql(order_sql)
    )
  end
end
