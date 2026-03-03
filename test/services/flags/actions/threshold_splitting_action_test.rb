require "test_helper"

class Flags::Actions::ThresholdSplittingActionTest < ActiveSupport::TestCase
  THRESHOLDS = Flags::Actions::ThresholdSplittingAction::THRESHOLDS

  def create_contract(external_id:, base_price:)
    Contract.create!(
      external_id: external_id,
      country_code: "PT",
      object: "Contrato #{external_id}",
      procedure_type: "Ajuste Direto",
      base_price: base_price,
      contracting_entity: entities(:one),
      data_source: data_sources(:portal_base)
    )
  end

  test "fires for a price just below the €20k threshold" do
    # 5% window below €20,000 = [€19,000, €20,000)
    anomalous = create_contract(external_id: "a5-20k", base_price: 19_500)

    assert_difference "Flag.count", 1 do
      result = Flags::Actions::ThresholdSplittingAction.new.call
      assert_equal 1, result
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A5_THRESHOLD_SPLITTING")
    assert_equal "medium", flag.severity
    assert_not_nil flag.score
    assert_equal "20000.0", flag.details["threshold"]
    assert_equal "19500.0", flag.details["base_price"]
  end

  test "fires for a price just below the €5k threshold" do
    anomalous = create_contract(external_id: "a5-5k", base_price: 4_900)

    assert_difference "Flag.count", 1 do
      Flags::Actions::ThresholdSplittingAction.new.call
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A5_THRESHOLD_SPLITTING")
    assert_equal "5000.0", flag.details["threshold"]
  end

  test "fires for a price at the exact lower bound of the window" do
    # 5% below €75,000 = €71,250
    anomalous = create_contract(external_id: "a5-75k-floor", base_price: 71_250)

    assert_difference "Flag.count", 1 do
      Flags::Actions::ThresholdSplittingAction.new.call
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A5_THRESHOLD_SPLITTING")
    assert_equal "75000.0", flag.details["threshold"]
  end

  test "does not fire for a price at the threshold itself" do
    create_contract(external_id: "a5-exact-20k", base_price: 20_000)

    assert_no_difference "Flag.count" do
      result = Flags::Actions::ThresholdSplittingAction.new.call
      assert_equal 0, result
    end
  end

  test "does not fire for a price below the 5% window" do
    # More than 5% below €20k
    create_contract(external_id: "a5-too-low", base_price: 18_000)

    assert_no_difference "Flag.count" do
      Flags::Actions::ThresholdSplittingAction.new.call
    end
  end

  test "does not fire when base_price is nil" do
    create_contract(external_id: "a5-nil", base_price: nil)

    assert_no_difference "Flag.count" do
      Flags::Actions::ThresholdSplittingAction.new.call
    end
  end

  test "flags contracts near multiple thresholds independently" do
    create_contract(external_id: "a5-near-5k",   base_price: 4_800)
    create_contract(external_id: "a5-near-150k", base_price: 148_000)

    assert_difference "Flag.count", 2 do
      result = Flags::Actions::ThresholdSplittingAction.new.call
      assert_equal 2, result
    end
  end

  test "is idempotent" do
    create_contract(external_id: "a5-idem", base_price: 19_999)

    action = Flags::Actions::ThresholdSplittingAction.new
    assert_equal 1, action.call
    assert_no_difference "Flag.count" do
      assert_equal 1, action.call
    end
  end

  test "removes stale flags when price is corrected" do
    contract = create_contract(external_id: "a5-stale", base_price: 19_500)

    action = Flags::Actions::ThresholdSplittingAction.new
    action.call
    assert_equal 1, Flag.where(contract_id: contract.id).count

    contract.update!(base_price: 25_000)

    assert_equal 0, action.call
    assert_equal 0, Flag.where(contract_id: contract.id).count
  end
end
