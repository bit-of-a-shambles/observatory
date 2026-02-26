require "test_helper"

class ContractWinnerTest < ActiveSupport::TestCase
  test "belongs to contract" do
    cw = contract_winners(:one)
    assert_instance_of Contract, cw.contract
  end

  test "belongs to entity" do
    cw = contract_winners(:one)
    assert_instance_of Entity, cw.entity
  end

  test "price_share can be nil" do
    cw = ContractWinner.new(contract: contracts(:one), entity: entities(:two))
    assert cw.valid?
  end

  test "price_share stores decimal value" do
    cw = contract_winners(:one)
    assert_equal 9.99, cw.price_share.to_f
  end
end
