require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  def create_contract!(external_id:, object:)
    Contract.create!(
      external_id: external_id,
      country_code: "PT",
      object: object,
      procedure_type: "Ajuste Direto",
      base_price: 1000,
      publication_date: Date.new(2025, 1, 10),
      celebration_date: Date.new(2025, 1, 12),
      contracting_entity: entities(:one),
      data_source: data_sources(:portal_base)
    )
  end

  test "index renders successfully" do
    get contracts_url
    assert_response :success
  end

  test "index filters by search query" do
    get contracts_url, params: { q: "supply" }
    assert_response :success
  end

  test "index filters by procedure type" do
    get contracts_url, params: { procedure_type: "Ajuste Direto" }
    assert_response :success
  end

  test "index filters by country" do
    get contracts_url, params: { country: "PT" }
    assert_response :success
  end

  test "index paginates with page param" do
    get contracts_url, params: { page: 2 }
    assert_response :success
  end

  test "index filters flagged contracts only" do
    flagged = create_contract!(external_id: "flagged-index-1", object: "Flagged Contract Alpha")
    unflagged = create_contract!(external_id: "flagged-index-2", object: "Unflagged Contract Beta")
    Flag.create!(
      contract: flagged,
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    get contracts_url, params: { flagged: "only" }
    assert_response :success
    assert_includes response.body, flagged.object
    assert_not_includes response.body, unflagged.object
  end

  test "index filters unflagged contracts only" do
    flagged = create_contract!(external_id: "flagged-index-3", object: "Flagged Contract Gamma")
    unflagged = create_contract!(external_id: "flagged-index-4", object: "Unflagged Contract Delta")
    Flag.create!(
      contract: flagged,
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )

    get contracts_url, params: { flagged: "none" }
    assert_response :success
    assert_includes response.body, unflagged.object
    assert_not_includes response.body, flagged.object
  end

  test "index filters by flag_type" do
    contract_a = create_contract!(external_id: "flagged-index-5", object: "Date anomaly contract")
    contract_b = create_contract!(external_id: "flagged-index-6", object: "Other anomaly contract")
    Flag.create!(
      contract: contract_a,
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: Time.current
    )
    Flag.create!(
      contract: contract_b,
      flag_type: "A1_REPEAT_DIRECT_AWARD",
      severity: "medium",
      score: 20,
      fired_at: Time.current
    )

    get contracts_url, params: { flag_type: "A2_PUBLICATION_AFTER_CELEBRATION" }
    assert_response :success
    assert_includes response.body, contract_a.object
    assert_not_includes response.body, contract_b.object
  end

  test "show renders a contract" do
    get contract_url(contracts(:one))
    assert_response :success
  end
end
