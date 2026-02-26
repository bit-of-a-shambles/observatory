require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
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

  test "show renders a contract" do
    get contract_url(contracts(:one))
    assert_response :success
  end
end
