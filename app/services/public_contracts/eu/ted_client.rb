# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PublicContracts
  module EU
    class TedClient
      SOURCE_NAME = "TED — Tenders Electronic Daily"
      BASE_URL    = "https://api.ted.europa.eu"
      API_VERSION = "v3"

      DEFAULT_FIELDS = %w[
        publication-number
        publication-date
        notice-title
        organisation-country-buyer
        organisation-name-buyer
      ].freeze

      def initialize(config = {})
        @api_key      = config.fetch("api_key", ENV["TED_API_KEY"])
        @country_code = config.fetch("country_code", "PRT")  # ISO 3166-1 alpha-3 for EQL queries
      end

      def country_code = "EU"
      def source_name  = SOURCE_NAME

      def search(query:, page: 1, limit: 10, fields: DEFAULT_FIELDS)
        body = { query: query, fields: fields, page: page, limit: limit }
        post("/#{API_VERSION}/notices/search", body)
      end

      def portuguese_contracts(page: 1, limit: 10)
        notices_for_country("PRT", page: page, limit: limit)
      end

      def notices_for_country(country_code, keyword: nil, page: 1, limit: 10)
        q = "organisation-country-buyer=#{country_code}"
        q += " AND #{keyword}" if keyword
        search(query: q, page: page, limit: limit)
      end

      def fetch_contracts(page: 1, limit: 50)
        result = search(query: "organisation-country-buyer=#{@country_code}", page: page, limit: limit)
        Array(result&.dig("notices"))
      end

      private

      def post(path, body)
        uri  = URI("#{BASE_URL}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = 15
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Accept"]       = "application/json"
        request["api-key"]      = @api_key if @api_key
        request.body            = body.to_json

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          log_error(response)
          nil
        end
      rescue StandardError => e
        log_exception(e)
        nil
      end

      def log_error(response)
        rails_log("[TedClient] HTTP #{response.code}: #{response.message}")
      end

      def log_exception(error)
        rails_log("[TedClient] #{error.class}: #{error.message}")
      end

      def rails_log(msg)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error msg
        else
          warn msg
        end
      end
    end
  end
end
