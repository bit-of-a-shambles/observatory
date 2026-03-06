# frozen_string_literal: true

require "test_helper"

class EntitiesControllerTest < ActionDispatch::IntegrationTest
  test "index renders successfully" do
    get entities_url
    assert_response :success
  end

  test "index filters by search query" do
    get entities_url, params: { q: "Lisboa" }
    assert_response :success
    assert_includes response.body, entities(:one).name
  end

  test "index filters by type public" do
    get entities_url, params: { type: "public" }
    assert_response :success
    assert_includes response.body, entities(:one).name
  end

  test "index filters by type private" do
    get entities_url, params: { type: "private" }
    assert_response :success
    assert_includes response.body, entities(:two).name
  end

  test "index paginates with page param" do
    get entities_url, params: { page: 2 }
    assert_response :success
  end

  test "index short query (1 char) returns all entities unfiltered" do
    get entities_url, params: { q: "L" }
    assert_response :success
  end

  test "show renders entity with contracts" do
    get entity_url(entities(:one))
    assert_response :success
    assert_includes response.body, entities(:one).name
  end

  test "show sorts contracts by base_price" do
    get entity_url(entities(:one), sort: "base_price", dir: "asc")
    assert_response :success
  end

  test "show sorts contracts by object" do
    get entity_url(entities(:one), sort: "object", dir: "asc")
    assert_response :success
  end

  test "show sorts contracts by celebration_date descending" do
    get entity_url(entities(:one), sort: "celebration_date", dir: "desc")
    assert_response :success
  end

  test "show paginates contracts" do
    get entity_url(entities(:one), page: 2)
    assert_response :success
  end

  test "show uses default sort when invalid sort param given" do
    get entity_url(entities(:one), sort: "invalid_col", dir: "sideways")
    assert_response :success
  end

  test "show filters contracts by flag_type" do
    get entity_url(entities(:one), flag_type: "A2")
    assert_response :success
  end

  test "show filters flagged contracts inside the turbo frame without crashing" do
    flag_type = "A2_PUBLICATION_AFTER_CELEBRATION"

    Flag.create!(
      contract: contracts(:one),
      flag_type: flag_type,
      severity: "high",
      score: 40,
      details: { rule: "A2/A3 date sequence anomaly" },
      fired_at: Time.current
    )

    FlagEntityStat.create!(
      entity: entities(:one),
      flag_type: flag_type,
      severity: "high",
      total_exposure: contracts(:one).base_price,
      contract_count: 1,
      computed_at: Time.current
    )

    get entity_url(entities(:one), flag_type: flag_type), headers: { "Turbo-Frame" => "entity-contracts" }

    assert_response :success
    assert_includes response.body, contracts(:one).object
    assert_not_includes response.body, contracts(:two).object
  end

  test "show filters contracts by date_from" do
    contracts(:one).update!(publication_date: Date.new(2025, 6, 1))
    contracts(:two).update!(publication_date: Date.new(2025, 1, 1))

    get entity_url(entities(:one), date_from: "2025-06-01"), headers: { "Turbo-Frame" => "entity-contracts" }
    assert_response :success
    assert_includes response.body, contracts(:one).object
    assert_not_includes response.body, contracts(:two).object
  end

  test "show filters contracts by date_to" do
    contracts(:one).update!(publication_date: Date.new(2025, 6, 1))
    contracts(:two).update!(publication_date: Date.new(2025, 1, 1))

    get entity_url(entities(:one), date_to: "2025-01-31"), headers: { "Turbo-Frame" => "entity-contracts" }
    assert_response :success
    assert_not_includes response.body, contracts(:one).object
    assert_includes response.body, contracts(:two).object
  end
end
