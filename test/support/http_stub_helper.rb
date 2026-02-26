# test/support/http_stub_helper.rb
module HttpStubHelper
  # Build a fake Net::HTTPSuccess-like response object.
  def fake_success(body)
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |klass| klass <= Net::HTTPSuccess }
    resp.define_singleton_method(:body)  { body }
    resp.define_singleton_method(:code)  { "200" }
    resp.define_singleton_method(:message) { "OK" }
    resp
  end

  # Build a fake error response (e.g. 404, 500).
  def fake_error(code = "500", message = "Internal Server Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:body)  { "" }
    resp.define_singleton_method(:code)  { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  # Stub Net::HTTP.get_response (used by BaseClient#get).
  def stub_get_response(response, &block)
    Net::HTTP.stub(:get_response, response, &block)
  end

  # Build a mock HTTP instance for POST requests (TedClient interface).
  def mock_http_post(response)
    mock = Minitest::Mock.new
    mock.expect(:use_ssl=,      nil, [ TrueClass ])
    mock.expect(:open_timeout=, nil, [ Integer ])
    mock.expect(:read_timeout=, nil, [ Integer ])
    mock.expect(:request,       response, [ Net::HTTP::Post ])
    mock
  end
end
