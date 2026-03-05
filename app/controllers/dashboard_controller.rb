class DashboardController < ApplicationController
  include ActionView::Helpers::NumberHelper

  STATS_CACHE_TTL = 5.minutes

  def index
    @severity_filter = params[:severity].presence
    flags_scope = @severity_filter ? Flag.where(severity: @severity_filter) : Flag

    # Keep as AR relation (subquery) — avoids loading 37K+ IDs into Ruby memory
    # and emitting a huge WHERE id IN (1,2,3,...) to SQLite
    flagged_subquery = flags_scope.select(:contract_id).distinct

    flags_count        = flags_scope.count
    @flag_types        = Rails.cache.fetch("dashboard/flag_types", expires_in: STATS_CACHE_TTL) { Flag.distinct.order(:flag_type).pluck(:flag_type) }
    @flags_by_type     = flags_scope.group(:flag_type).order(:flag_type).count
    @insights_count    = flags_count
    @entity_sort       = params[:entity_sort] == "count" ? "count" : "value"
    @entity_flag_type  = params[:entity_flag_type].presence
    @entity_exposure_rows = entity_exposure_rows(sort_by: @entity_sort, flag_type: @entity_flag_type, severity: @severity_filter)

    # Cache full-table counts — these barely change between page loads
    contract_count = Rails.cache.fetch("dashboard/contract_count", expires_in: STATS_CACHE_TTL) { Contract.count }
    entity_count   = Rails.cache.fetch("dashboard/entity_count",   expires_in: STATS_CACHE_TTL) { Entity.count }

    @stats = [
      { label: t("stats.contracts"), value: number_with_delimiter(contract_count), color: "text-[#c8a84e]" },
      { label: t("stats.entities"),  value: number_with_delimiter(entity_count),   color: "text-[#e8e0d4]" },
      { label: t("stats.sources"),   value: DataSource.where(status: :active).count.to_s, color: "text-[#e8e0d4]" },
      { label: t("stats.alerts"),    value: number_with_delimiter(flags_count),    color: "text-[#ff4444]" }
    ]

    source_contract_counts = Rails.cache.fetch("dashboard/source_contract_counts", expires_in: STATS_CACHE_TTL) do
      Contract.where.not(data_source_id: nil).group(:data_source_id).count
    end

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

    # All three aggregates use the subquery — SQL decides the join strategy,
    # no large arrays passed through Ruby
    @flagged_total_exposure = Contract.where(id: flagged_subquery).sum(:base_price)
    @flagged_contract_count = flagged_subquery.count

    @flagged_companies_count = Entity
      .joins(:contract_winners)
      .where(contract_winners: { contract_id: flagged_subquery })
      .where(is_company: true)
      .distinct
      .count

    @flagged_public_entities_count = Contract
      .where(id: flagged_subquery)
      .joins(:contracting_entity)
      .where(entities: { is_public_body: true })
      .distinct
      .count(:contracting_entity_id)

    # Single GROUP BY instead of two separate COUNT queries
    entity_type_counts = Rails.cache.fetch("dashboard/entity_type_counts", expires_in: STATS_CACHE_TTL) do
      Entity.group(:is_public_body).count
    end

    @crossings = [
      { label: t("dashboard.crossings.contracts_with_winners"), count: number_with_delimiter(entity_type_counts[false] || 0) },
      { label: t("dashboard.crossings.public_bodies"),          count: number_with_delimiter(entity_type_counts[true]  || 0) },
      { label: t("dashboard.crossings.ecfp_donors"),            count: "—" },
      { label: t("dashboard.crossings.tdc_sanctions"),          count: "—" }
    ]
  end

  private

  def entity_exposure_rows(sort_by:, flag_type:, severity: nil)
    scope = Flag.joins(contract: :contracting_entity)
    scope = scope.where(flag_type: flag_type) if flag_type.present?
    scope = scope.where(severity: severity) if severity.present?

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
