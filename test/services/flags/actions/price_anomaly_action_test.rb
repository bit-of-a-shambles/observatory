require "test_helper"

class Flags::Actions::PriceAnomalyActionTest < ActiveSupport::TestCase
  def create_contract(external_id:, base_price:, total_effective_price:)
    Contract.create!(
      external_id: external_id,
      country_code: "PT",
      object: "Contrato #{external_id}",
      procedure_type: "Ajuste Direto",
      base_price: base_price,
      total_effective_price: total_effective_price,
      contracting_entity: entities(:one),
      data_source: data_sources(:portal_base)
    )
  end

  test "creates a flag when total_effective_price is more than 1.5x base_price" do
    anomalous = create_contract(
      external_id: "a9-over",
      base_price: 1000,
      total_effective_price: 1600
    )

    assert_difference "Flag.count", 1 do
      result = Flags::Actions::PriceAnomalyAction.new.call
      assert_equal 1, result
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A9_PRICE_ANOMALY")
    assert_equal "medium", flag.severity
    assert_not_nil flag.score
    assert_equal "1000.0", flag.details["base_price"]
    assert_equal "1600.0", flag.details["total_effective_price"]
    assert_in_delta 1.6, flag.details["ratio"].to_f, 0.001
  end

  test "creates a flag when total_effective_price is less than 0.5x base_price" do
    anomalous = create_contract(
      external_id: "a9-under",
      base_price: 1000,
      total_effective_price: 400
    )

    assert_difference "Flag.count", 1 do
      Flags::Actions::PriceAnomalyAction.new.call
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A9_PRICE_ANOMALY")
    assert_in_delta 0.4, flag.details["ratio"].to_f, 0.001
  end

  test "does not fire when ratio is within [0.5, 1.5]" do
    create_contract(external_id: "a9-ok-high", base_price: 1000, total_effective_price: 1500)
    create_contract(external_id: "a9-ok-low",  base_price: 1000, total_effective_price: 500)
    create_contract(external_id: "a9-ok-mid",  base_price: 1000, total_effective_price: 900)

    assert_no_difference "Flag.count" do
      result = Flags::Actions::PriceAnomalyAction.new.call
      assert_equal 0, result
    end
  end

  test "does not fire when base_price is nil" do
    create_contract(external_id: "a9-nil-base", base_price: nil, total_effective_price: 500)

    assert_no_difference "Flag.count" do
      Flags::Actions::PriceAnomalyAction.new.call
    end
  end

  test "does not fire when total_effective_price is nil" do
    create_contract(external_id: "a9-nil-total", base_price: 1000, total_effective_price: nil)

    assert_no_difference "Flag.count" do
      Flags::Actions::PriceAnomalyAction.new.call
    end
  end

  test "does not fire when base_price is zero" do
    create_contract(external_id: "a9-zero-base", base_price: 0, total_effective_price: 500)

    assert_no_difference "Flag.count" do
      Flags::Actions::PriceAnomalyAction.new.call
    end
  end

  test "is idempotent" do
    create_contract(external_id: "a9-idempotent", base_price: 1000, total_effective_price: 2000)

    action = Flags::Actions::PriceAnomalyAction.new
    assert_equal 1, action.call
    assert_no_difference "Flag.count" do
      assert_equal 1, action.call
    end
  end

  test "removes stale flags when contract prices are corrected" do
    contract = create_contract(
      external_id: "a9-stale",
      base_price: 1000,
      total_effective_price: 2000
    )

    action = Flags::Actions::PriceAnomalyAction.new
    action.call
    assert_equal 1, Flag.where(contract_id: contract.id).count

    contract.update!(total_effective_price: 1100)

    assert_equal 0, action.call
    assert_equal 0, Flag.where(contract_id: contract.id).count
  end
end
