require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def create_public_entity!(name:, tax_identifier:)
    Entity.create!(
      name: name,
      tax_identifier: tax_identifier,
      country_code: "PT",
      is_public_body: true,
      is_company: false
    )
  end

  def create_company!(name:, tax_identifier:)
    Entity.create!(
      name: name,
      tax_identifier: tax_identifier,
      country_code: "PT",
      is_public_body: false,
      is_company: true
    )
  end

  def create_flagged_contract!(external_id:, object:, flag_type:, base_price: 2500, contracting_entity: entities(:one), winners: [])
    contract = Contract.create!(
      external_id: external_id,
      country_code: "PT",
      object: object,
      procedure_type: "Ajuste Direto",
      base_price: base_price,
      publication_date: Date.new(2025, 1, 10),
      celebration_date: Date.new(2025, 1, 8),
      contracting_entity: contracting_entity,
      data_source: data_sources(:portal_base)
    )

    winners.each do |winner|
      ContractWinner.create!(contract: contract, entity: winner)
    end

    Flag.create!(
      contract: contract,
      flag_type: flag_type,
      severity: "high",
      score: 40,
      details: { "rule" => "A2/A3 date sequence anomaly" },
      fired_at: Time.current
    )
    contract
  end

  test "should get index" do
    get dashboard_index_url
    assert_response :success
  end

  test "dashboard shows real flagged aggregates" do
    contract = create_flagged_contract!(
      external_id: "dashboard-flag-1",
      object: "Contrato com anomalia temporal",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION"
    )

    get dashboard_index_url
    assert_response :success
    assert_includes response.body, contract.contracting_entity.name
    assert_includes response.body, "A2 PUBLICATION AFTER CELEBRATION"
    assert_not_includes response.body, "Auto-direcionamento de emendas"
  end

  test "dashboard shows total exposure and distinct involved entities" do
    public_a = create_public_entity!(name: "Public Body Exposure Alpha", tax_identifier: "599000111")
    public_b = create_public_entity!(name: "Public Body Exposure Beta", tax_identifier: "599000112")
    company_a = create_company!(name: "Company Exposure Alpha", tax_identifier: "599100111")
    company_b = create_company!(name: "Company Exposure Beta", tax_identifier: "599100112")

    create_flagged_contract!(
      external_id: "dashboard-metrics-1",
      object: "Contrato Exposição 1",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      base_price: 4000,
      contracting_entity: public_a,
      winners: [ company_a ]
    )
    create_flagged_contract!(
      external_id: "dashboard-metrics-2",
      object: "Contrato Exposição 2",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      base_price: 6000,
      contracting_entity: public_b,
      winners: [ company_b ]
    )

    get dashboard_index_url
    assert_response :success

    assert_includes response.body, "€10,000.00"
    assert_includes response.body, I18n.t("dashboard.exposure.companies", count: 2)
    assert_includes response.body, I18n.t("dashboard.exposure.public_entities", count: 2)
  end

  test "dashboard entity exposure can be sorted by value and count per flag" do
    alpha = create_public_entity!(name: "Sort Entity Alpha", tax_identifier: "599200111")
    beta = create_public_entity!(name: "Sort Entity Beta", tax_identifier: "599200112")

    create_flagged_contract!(
      external_id: "dashboard-sort-1",
      object: "Sort Contract Alpha",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      base_price: 9000,
      contracting_entity: alpha
    )
    create_flagged_contract!(
      external_id: "dashboard-sort-2",
      object: "Sort Contract Beta 1",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      base_price: 1900,
      contracting_entity: beta
    )
    create_flagged_contract!(
      external_id: "dashboard-sort-3",
      object: "Sort Contract Beta 2",
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      base_price: 2100,
      contracting_entity: beta
    )

    get dashboard_index_url, params: {
      entity_flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      entity_sort: "value"
    }
    assert_response :success
    assert_operator response.body.index("€9,000.00"), :<, response.body.index("€4,000.00")

    get dashboard_index_url, params: {
      entity_flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      entity_sort: "count"
    }
    assert_response :success
    assert_operator response.body.index("€4,000.00"), :<, response.body.index("€9,000.00")
  end

  test "dashboard sources pane uses real contract counts instead of stale metadata" do
    data_sources(:portal_base).update!(record_count: 0, status: :active)

    get dashboard_index_url
    assert_response :success
    assert_match(/Portal BASE.*2 records/m, response.body)
  end
end
