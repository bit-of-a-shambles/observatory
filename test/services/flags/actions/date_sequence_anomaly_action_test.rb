require "test_helper"

class Flags::Actions::DateSequenceAnomalyActionTest < ActiveSupport::TestCase
  def create_contract(external_id:, publication_date:, celebration_date:)
    Contract.create!(
      external_id: external_id,
      country_code: "PT",
      object: "Contrato #{external_id}",
      procedure_type: "Ajuste Direto",
      base_price: 1000,
      publication_date: publication_date,
      celebration_date: celebration_date,
      contracting_entity: entities(:one),
      data_source: data_sources(:portal_base)
    )
  end

  test "creates a flag when celebration date is before publication date" do
    anomalous = create_contract(
      external_id: "rule-a2-1",
      publication_date: Date.new(2025, 1, 10),
      celebration_date: Date.new(2025, 1, 8)
    )
    create_contract(
      external_id: "rule-a2-2",
      publication_date: Date.new(2025, 1, 10),
      celebration_date: Date.new(2025, 1, 11)
    )

    assert_difference "Flag.count", 1 do
      result = Flags::Actions::DateSequenceAnomalyAction.new.call
      assert_equal 1, result
    end

    flag = Flag.find_by!(contract_id: anomalous.id, flag_type: "A2_PUBLICATION_AFTER_CELEBRATION")
    assert_equal "high", flag.severity
    assert_equal 40, flag.score
    assert_equal "2025-01-10", flag.details["publication_date"]
    assert_equal "2025-01-08", flag.details["celebration_date"]
    assert_equal "A2/A3 date sequence anomaly", flag.details["rule"]
  end

  test "is idempotent for the same anomalous contract" do
    create_contract(
      external_id: "rule-a2-idempotent",
      publication_date: Date.new(2025, 2, 10),
      celebration_date: Date.new(2025, 2, 5)
    )

    action = Flags::Actions::DateSequenceAnomalyAction.new
    assert_equal 1, action.call
    assert_no_difference "Flag.count" do
      assert_equal 1, action.call
    end
  end

  test "removes stale flags when contract no longer matches the anomaly" do
    contract = create_contract(
      external_id: "rule-a2-stale",
      publication_date: Date.new(2025, 3, 20),
      celebration_date: Date.new(2025, 3, 10)
    )

    action = Flags::Actions::DateSequenceAnomalyAction.new
    action.call
    assert_equal 1, Flag.where(contract_id: contract.id).count

    contract.update!(celebration_date: Date.new(2025, 3, 21))

    assert_equal 0, action.call
    assert_equal 0, Flag.where(contract_id: contract.id).count
  end

  test "removes stale flags when non matching contracts exist and anomalies still exist" do
    anomalous = create_contract(
      external_id: "rule-a2-kept",
      publication_date: Date.new(2025, 4, 15),
      celebration_date: Date.new(2025, 4, 10)
    )
    normal = create_contract(
      external_id: "rule-a2-cleared",
      publication_date: Date.new(2025, 4, 10),
      celebration_date: Date.new(2025, 4, 11)
    )
    Flag.create!(
      contract: normal,
      flag_type: "A2_PUBLICATION_AFTER_CELEBRATION",
      severity: "high",
      score: 40,
      fired_at: 2.days.ago
    )

    result = Flags::Actions::DateSequenceAnomalyAction.new.call
    assert_equal 1, result

    assert Flag.exists?(contract_id: anomalous.id, flag_type: "A2_PUBLICATION_AFTER_CELEBRATION")
    assert_not Flag.exists?(contract_id: normal.id, flag_type: "A2_PUBLICATION_AFTER_CELEBRATION")
  end
end
