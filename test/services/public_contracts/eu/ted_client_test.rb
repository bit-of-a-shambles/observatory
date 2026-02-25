require "test_helper"

class PublicContracts::EU::TedClientTest < ActiveSupport::TestCase
  NOTICES_PAYLOAD = {
    "notices"          => [{ "publication-number" => "2026/S001-001" }],
    "totalNoticeCount" => 32000
  }.freeze

  def fake_success(body)
    resp = Net::HTTPSuccess.new("1.1", "200", "OK")
    resp.instance_variable_set(:@body, body)
    resp.define_singleton_method(:body) { body }
    resp
  end

  def fake_error(code = "500", message = "Server Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:body)  { "" }
    resp.define_singleton_method(:code)  { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  def mock_http_post(response)
    mock = Minitest::Mock.new
    mock.expect(:use_ssl=,      nil, [TrueClass])
    mock.expect(:open_timeout=, nil, [Integer])
    mock.expect(:read_timeout=, nil, [Integer])
    mock.expect(:request,       response, [Net::HTTP::Post])
    mock
  end

  setup do
    @client = PublicContracts::EU::TedClient.new
  end

  test "source_name" do
    assert_equal "TED — Tenders Electronic Daily", @client.source_name
  end

  test "country_code is EU" do
    assert_equal "EU", @client.country_code
  end

  test "search returns parsed response on success" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.search(query: "organisation-country-buyer=PRT")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "search returns nil on HTTP error" do
    mock = mock_http_post(fake_error("500", "Server Error"))
    Net::HTTP.stub(:new, mock) do
      result = @client.search(query: "organisation-country-buyer=PRT")
      assert_nil result
    end
    mock.verify
  end

  test "search returns nil on network exception" do
    raising_mock = Object.new
    raising_mock.define_singleton_method(:use_ssl=)      { |_| }
    raising_mock.define_singleton_method(:open_timeout=) { |_| }
    raising_mock.define_singleton_method(:read_timeout=) { |_| }
    raising_mock.define_singleton_method(:request)       { |_| raise Errno::ECONNREFUSED }
    Net::HTTP.stub(:new, raising_mock) do
      result = @client.search(query: "test")
      assert_nil result
    end
  end

  test "portuguese_contracts calls search with PRT" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.portuguese_contracts(limit: 5)
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "notices_for_country without keyword" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.notices_for_country("ESP")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "notices_for_country with keyword" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.notices_for_country("PRT", keyword: "construction")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "fetch_contracts returns notices array" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal NOTICES_PAYLOAD["notices"], result
    end
    mock.verify
  end

  test "fetch_contracts returns empty array when search fails" do
    mock = mock_http_post(fake_error)
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
    mock.verify
  end

  test "accepts api_key from config" do
    client = PublicContracts::EU::TedClient.new("api_key" => "test-key")
    assert_instance_of PublicContracts::EU::TedClient, client
  end

  test "rails_log falls back to warn when Rails logger is nil" do
    original_logger = Rails.logger
    Rails.logger = nil
    warning_issued = false
    raising_mock = Object.new
    raising_mock.define_singleton_method(:use_ssl=)      { |_| }
    raising_mock.define_singleton_method(:open_timeout=) { |_| }
    raising_mock.define_singleton_method(:read_timeout=) { |_| }
    raising_mock.define_singleton_method(:request)       { |_| raise StandardError, "no logger test" }
    @client.stub(:warn, ->(_msg) { warning_issued = true }) do
      Net::HTTP.stub(:new, raising_mock) do
        result = @client.search(query: "test")
        assert_nil result
      end
    end
    assert warning_issued, "expected warn to be called when Rails.logger is nil"
  ensure
    Rails.logger = original_logger
  end
end
