require "test_helper"

class ContractTest < ActiveSupport::TestCase
  test "valid contract" do
    contract = Contract.new(
      external_id:        "ext-999",
      object:             "Test procurement",
      country_code:       "PT",
      contracting_entity: entities(:one)
    )
    assert contract.valid?
  end

  test "invalid without external_id" do
    contract = Contract.new(object: "Test", country_code: "PT",
                            contracting_entity: entities(:one))
    assert_not contract.valid?
  end

  test "invalid without object" do
    contract = Contract.new(external_id: "ext-999", country_code: "PT",
                            contracting_entity: entities(:one))
    assert_not contract.valid?
  end

  test "external_id must be unique within country" do
    existing = contracts(:one)
    dup = Contract.new(
      external_id:        existing.external_id,
      country_code:       existing.country_code,
      object:             "Another",
      contracting_entity: entities(:one)
    )
    assert_not dup.valid?
    assert_includes dup.errors.details[:external_id].map { |e| e[:error] }, :taken
  end

  test "same external_id allowed in different countries" do
    existing = contracts(:one)
    other = Contract.new(
      external_id:        existing.external_id,
      country_code:       "ES",
      object:             "Spanish contract",
      contracting_entity: entities(:one)
    )
    assert other.valid?
  end

  test "belongs to contracting_entity" do
    assert_equal entities(:one), contracts(:one).contracting_entity
  end

  test "belongs to data_source (optional)" do
    assert_equal data_sources(:portal_base), contracts(:one).data_source
  end

  test "data_source is optional" do
    contract = Contract.new(
      external_id:        "ext-888",
      object:             "No source",
      country_code:       "PT",
      contracting_entity: entities(:one)
    )
    assert contract.valid?
  end

  test "has many contract_winners" do
    assert_respond_to contracts(:one), :contract_winners
  end

  test "has many winners through contract_winners" do
    assert_respond_to contracts(:one), :winners
  end

  test "has many flags" do
    assert_respond_to contracts(:one), :flags
  end

  test "contract_winners destroyed with contract" do
    contract = contracts(:one)
    winner_count = contract.contract_winners.count
    assert winner_count > 0
    contract.destroy
    assert_equal 0, ContractWinner.where(contract_id: contract.id).count
  end

  test "flags destroyed with contract" do
    contract = contracts(:one)
    Flag.create!(
      contract: contract,
      flag_type: "TEST_FLAG",
      severity: "high",
      score: 10,
      fired_at: Time.current
    )

    assert_equal 1, Flag.where(contract_id: contract.id).count
    contract.destroy
    assert_equal 0, Flag.where(contract_id: contract.id).count
  end
end
