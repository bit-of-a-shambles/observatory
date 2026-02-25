require "simplecov"
SimpleCov.start "rails"

require "minitest/autorun"

# Load the API key from .env (simple key=value parser, no gem required)
env_file = File.expand_path("../../../.env", __dir__)
if File.exist?(env_file)
  File.foreach(env_file) do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key.upcase] = value if key && value
  end
end

require_relative "../../../app/services/public_contracts/eu/ted_client"

# Integration test — hits api.ted.europa.eu live.
# Run with:  bundle exec ruby test/services/public_contracts/ted_client_test.rb
class TedClientTest < Minitest::Test
  def setup
    @client = PublicContracts::EU::TedClient.new
  end

  def test_api_key_loaded_from_env
    assert ENV["TED_API_KEY"], "TED_API_KEY must be set (loaded from .env)"
    refute_empty ENV["TED_API_KEY"]
  end

  def test_search_portuguese_contracts
    result = @client.portuguese_contracts(limit: 5)

    assert_kind_of Hash, result, "Expected a Hash response from TED API, got: #{result.inspect}"
    assert result.key?("notices"), "Response should have 'notices' key. Keys: #{result.keys.inspect}"

    notices = result["notices"]
    assert_kind_of Array, notices
    assert notices.size > 0, "Expected at least one notice"

    puts "\n  [TED] Portuguese procurement notices (#{notices.size} returned):"
    notices.each_with_index do |n, i|
      # notice-title is [[lang, text], ...] — grab the title text (index 1)
      title = Array(n["notice-title"]).map { |t| Array(t)[1] }.compact.first
      puts "  #{i + 1}. #{n['publication-number']} | #{n['publication-date']} | #{title&.slice(0, 80)}"
    end
  end

  def test_search_with_eql_query
    result = @client.search(query: "organisation-country-buyer=PRT", limit: 3)

    assert_kind_of Hash, result
    assert result["notices"].is_a?(Array), "Expected notices array"
    puts "\n  [TED] EQL search total count: #{result['totalNoticeCount'] || result['total'] || '(not in response)'}"
  end
end
