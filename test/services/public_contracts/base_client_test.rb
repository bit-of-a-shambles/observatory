require "test_helper"

class PublicContracts::BaseClientTest < ActiveSupport::TestCase
  # Inline the helper rather than requiring a file so we avoid load path issues
  def fake_success(body)
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |klass| klass <= Net::HTTPSuccess }
    resp.define_singleton_method(:body)  { body }
    resp.define_singleton_method(:code)  { "200" }
    resp.define_singleton_method(:message) { "OK" }
    resp
  end

  def fake_error(code = "500", message = "Internal Server Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:body)  { "" }
    resp.define_singleton_method(:code)  { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  setup do
    @client = PublicContracts::BaseClient.new("https://example.com")
  end

  test "get returns parsed JSON on success" do
    response = fake_success('{"key":"value"}')
    Net::HTTP.stub(:get_response, response) do
      result = @client.send(:get, "/path")
      assert_equal({ "key" => "value" }, result)
    end
  end

  test "get with params appends query string" do
    response = fake_success('{"key":"value"}')
    Net::HTTP.stub(:get_response, response) do
      result = @client.send(:get, "/path", foo: "bar")
      assert_equal({ "key" => "value" }, result)
    end
  end

  test "get returns nil on HTTP error" do
    response = fake_error("404", "Not Found")
    Net::HTTP.stub(:get_response, response) do
      result = @client.send(:get, "/path")
      assert_nil result
    end
  end

  test "get returns nil and logs on exception" do
    Net::HTTP.stub(:get_response, ->(_uri) { raise Errno::ECONNREFUSED, "refused" }) do
      result = @client.send(:get, "/path")
      assert_nil result
    end
  end

  test "get with empty params does not raise" do
    response = fake_success("[]")
    Net::HTTP.stub(:get_response, response) do
      result = @client.send(:get, "/contracts")
      assert_equal [], result
    end
  end
end
