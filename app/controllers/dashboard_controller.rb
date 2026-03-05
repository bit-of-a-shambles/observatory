class DashboardController < ApplicationController
  include ActionView::Helpers::NumberHelper

  STATS_CACHE_TTL    = 60.minutes
  EXPOSURE_ROW_LIMIT = 200

  def index
    @severity_filter  = params[:severity].presence
    @entity_sort      = params[:entity_sort] == "count" ? "count" : "value"
    @entity_flag_type = params[:entity_flag_type].presence

    # -----------------------------------------------------------------------
    # Stable counts — cheap queries, cache generously
    # -----------------------------------------------------------------------
    contract_count = Rails.cache.fetch("dashboard/contract_count", expires_in: STATS_CACHE_TTL) { Contract.count }
    entity_count   = Rails.cache.fetch("dashboard/entity_count",   expires_in: STATS_CACHE_TTL) { Entity.count }

    source_contract_counts = Rails.cache.fetch("dashboard/source_contract_counts", expires_in: STATS_CACHE_TTL) do
      Contract.where.not(data_source_id: nil).group(:data_source_id).count
    end

    entity_type_counts = Rails.cache.fetch("dashboard/entity_type_counts", expires_in: STATS_CACHE_TTL) do
      Entity.group(:is_public_body).count
    end

    # Flag type list — used to populate filter pills, cached for 1 h.
    @flag_types = Rails.cache.fetch("dashboard/flag_types", expires_in: STATS_CACHE_TTL) do
      Flag.distinct.order(:flag_type).pluck(:flag_type)
    end

    # Flag count + per-type breakdown — fast indexed queries, cached.
    flags_scope      = @severity_filter ? Flag.where(severity: @severity_filter) : Flag.all
    @insights_count  = Rails.cache.fetch("dashboard/flags_count/sev:#{@severity_filter}", expires_in: STATS_CACHE_TTL) { flags_scope.count }
    @flags_by_type   = Rails.cache.fetch("dashboard/flags_by_type/sev:#{@severity_filter}", expires_in: STATS_CACHE_TTL) do
      flags_scope.group(:flag_type).order(:flag_type).count
    end

    # -----------------------------------------------------------------------
    # Pre-computed aggregate totals — read from flag_summary_stats (single row
    # lookup), populated by flags:aggregate. Zero-fallback if not yet computed.
    # -----------------------------------------------------------------------
    summary = FlagSummaryStat.find_by(severity: @severity_filter)
    @flagged_total_exposure        = summary&.total_exposure || 0
    @flagged_contract_count        = summary&.flagged_contract_count || 0
    @flagged_companies_count       = summary&.flagged_companies_count || 0
    @flagged_public_entities_count = summary&.flagged_public_entities_count || 0

    # -----------------------------------------------------------------------
    # Entity exposure table — reads from flag_entity_stats (pre-aggregated),
    # never joins the flags table at request time.
    # -----------------------------------------------------------------------
    @entity_exposure_rows = entity_exposure_rows(
      sort_by:   @entity_sort,
      flag_type: @entity_flag_type,
      severity:  @severity_filter
    )

    active_sources_count = Rails.cache.fetch("dashboard/active_sources_count", expires_in: STATS_CACHE_TTL) do
      DataSource.where(status: :active).count
    end

    all_sources = Rails.cache.fetch("dashboard/all_sources", expires_in: STATS_CACHE_TTL) do
      DataSource.order(:country_code, :name).map do |ds|
        { id: ds.id, name: ds.name, country_code: ds.country_code,
          source_type: ds.source_type, status: ds.status,
          records: source_contract_counts.fetch(ds.id, 0),
          synced_at: ds.last_synced_at&.strftime("%Y-%m-%d %H:%M") }
      end
    end

    @stats = [
      { label: t("stats.contracts"), value: number_with_delimiter(contract_count),  color: "text-[#c8a84e]" },
      { label: t("stats.entities"),  value: number_with_delimiter(entity_count),    color: "text-[#e8e0d4]" },
      { label: t("stats.sources"),   value: active_sources_count.to_s,              color: "text-[#e8e0d4]" },
      { label: t("stats.alerts"),    value: number_with_delimiter(@insights_count), color: "text-[#ff4444]" }
    ]

    @sources = all_sources.map do |ds|
      {
        name:      ds[:name],
        country:   ds[:country_code],
        type:      ds[:source_type].capitalize,
        status:    ds[:status],
        records:   number_with_delimiter(ds[:records]),
        synced_at: ds[:synced_at]
      }
    end

    @crossings = [
      { label: t("dashboard.crossings.contracts_with_winners"), count: number_with_delimiter(entity_type_counts[false] || 0) },
      { label: t("dashboard.crossings.public_bodies"),          count: number_with_delimiter(entity_type_counts[true]  || 0) },
      { label: t("dashboard.crossings.ecfp_donors"),            count: "—" },
      { label: t("dashboard.crossings.tdc_sanctions"),          count: "—" }
    ]
  end

  private

  # Reads from the pre-aggregated flag_entity_stats table.
  # Groups by (flag_type, entity_id) to merge across severity variants so that
  # the unfiltered view shows one row per entity+flag combination (not one per
  # severity). When a severity filter is active, WHERE limits to that severity
  # and the GROUP BY collapses the single matching row.
  def entity_exposure_rows(sort_by:, flag_type:, severity:)
    scope = FlagEntityStat.joins(:entity)
    scope = scope.where(flag_type: flag_type) if flag_type.present?
    scope = scope.where(severity:  severity)  if severity.present?

    order_col = sort_by == "count" ? "exposure_count" : "exposure_value"

    scope
      .select(
        "flag_entity_stats.flag_type             AS flag_type",
        "entities.name                           AS entity_name",
        "SUM(flag_entity_stats.total_exposure)   AS exposure_value",
        "SUM(flag_entity_stats.contract_count)   AS exposure_count"
      )
      .group("flag_entity_stats.flag_type, flag_entity_stats.entity_id, entities.name")
      .order(Arel.sql("#{order_col} DESC, entities.name ASC"))
      .limit(EXPOSURE_ROW_LIMIT)
      .map { |r| { flag_type: r.flag_type, entity_name: r.entity_name,
                   exposure_value: r.exposure_value.to_f, exposure_count: r.exposure_count.to_i } }
  end
end
