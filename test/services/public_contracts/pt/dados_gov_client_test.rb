require "test_helper"

class PublicContracts::PT::DadosGovClientTest < ActiveSupport::TestCase
  def fake_success(body)
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |klass| klass <= Net::HTTPSuccess }
    resp.define_singleton_method(:body)  { body }
    resp
  end

  def fake_error
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:code)  { "500" }
    resp.define_singleton_method(:message) { "Error" }
    resp
  end

  setup do
    @client = PublicContracts::PT::DadosGovClient.new
  end

  test "country_code is PT" do
    assert_equal "PT", @client.country_code
  end

  test "source_name" do
    assert_equal "dados.gov.pt", @client.source_name
  end

  test "search_datasets returns parsed response" do
    payload = { "data" => [{ "id" => "abc" }] }
    Net::HTTP.stub(:get_response, fake_success(payload.to_json)) do
      result = @client.search_datasets("contratos")
      assert_equal payload, result
    end
  end

  test "search_datasets returns nil on error" do
    Net::HTTP.stub(:get_response, fake_error) do
      result = @client.search_datasets("contratos")
      assert_nil result
    end
  end

  test "fetch_resource returns parsed response" do
    payload = { "id" => "res-1", "url" => "https://example.com/file.csv" }
    Net::HTTP.stub(:get_response, fake_success(payload.to_json)) do
      result = @client.fetch_resource("res-1")
      assert_equal payload, result
    end
  end

  test "fetch_contracts extracts data array" do
    payload = { "data" => [{ "id" => "c1" }, { "id" => "c2" }] }
    Net::HTTP.stub(:get_response, fake_success(payload.to_json)) do
      result = @client.fetch_contracts
      assert_equal 2, result.size
    end
  end

  test "fetch_contracts returns empty array when error" do
    Net::HTTP.stub(:get_response, fake_error) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
  end
end
