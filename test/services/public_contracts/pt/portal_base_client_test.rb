require "test_helper"

class PublicContracts::PT::PortalBaseClientTest < ActiveSupport::TestCase
  def fake_success(body)
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |klass| klass <= Net::HTTPSuccess }
    resp.define_singleton_method(:body)  { body }
    resp
  end

  def fake_error(code = "500", message = "Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:code)  { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  setup do
    @client = PublicContracts::PT::PortalBaseClient.new
  end

  test "country_code is PT" do
    assert_equal "PT", @client.country_code
  end

  test "source_name is Portal BASE" do
    assert_equal "Portal BASE", @client.source_name
  end

  test "fetch_contracts returns array on success" do
    payload = [ { "id" => 1, "object" => "Serviços" } ]
    Net::HTTP.stub(:get_response, fake_success(payload.to_json)) do
      result = @client.fetch_contracts
      assert_equal payload, result
    end
  end

  test "fetch_contracts raises transient error on retryable status" do
    Net::HTTP.stub(:get_response, fake_error) do
      assert_raises(PublicContracts::PT::PortalBaseClient::TransientError) do
        @client.fetch_contracts
      end
    end
  end

  test "find_contract returns hash on success" do
    payload = { "id" => 42, "object" => "Test" }
    Net::HTTP.stub(:get_response, fake_success(payload.to_json)) do
      result = @client.find_contract(42)
      assert_equal payload, result
    end
  end

  test "find_contract returns nil on error" do
    Net::HTTP.stub(:get_response, fake_error("404", "Not Found")) do
      result = @client.find_contract(99)
      assert_nil result
    end
  end

  test "get returns nil on invalid JSON payload" do
    Net::HTTP.stub(:get_response, fake_success("not-json")) do
      assert_equal [], @client.fetch_contracts
    end
  end

  test "accepts base_url from config" do
    client = PublicContracts::PT::PortalBaseClient.new("base_url" => "https://custom.example.com")
    assert_instance_of PublicContracts::PT::PortalBaseClient, client
  end
end
