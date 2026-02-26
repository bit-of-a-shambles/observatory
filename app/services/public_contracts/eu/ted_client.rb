# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

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
        BT-105-Procedure
        BT-27-Procedure
        BT-27-Procedure-Currency
        main-classification-proc
        BT-5071-Procedure
      ].freeze

      # Maps TED ISO 3166-1 alpha-3 codes to alpha-2 used by the domain model
      COUNTRY_MAP = { "PRT" => "PT", "ESP" => "ES", "FRA" => "FR", "DEU" => "DE" }.freeze

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
        Array(result&.dig("notices")).map { |notice| normalize(notice) }
      end

      private

      # Maps a raw TED notice hash to the format ImportService expects.
      # TED notices don't carry buyer NIFs in the basic API fields, so we derive
      # a deterministic synthetic identifier from the buyer name to allow
      # deduplication across notices from the same organisation.
      #
      # Actual TED v3 field shapes:
      #   organisation-name-buyer   → {"eng" => ["Org Name"], ...}
      #   organisation-country-buyer → ["PRT"]
      #   notice-title              → {"eng" => "Portugal – ...", "por" => "...", ...}
      def normalize(notice)
        buyer_name = extract_buyer_name(notice["organisation-name-buyer"])
        buyer_id   = "TED-#{Digest::MD5.hexdigest(buyer_name.downcase.strip)[0, 12]}"
        alpha3     = Array(notice["organisation-country-buyer"]).first.to_s
        iso2       = COUNTRY_MAP.fetch(alpha3, "EU")

        {
          "external_id"        => notice["publication-number"],
          "country_code"       => iso2,
          "object"             => extract_title(notice["notice-title"]),
          "publication_date"   => notice["publication-date"]&.delete_suffix("Z"),
          "procedure_type"     => notice["BT-105-Procedure"],
          "base_price"         => notice["BT-27-Procedure"]&.then { |v| BigDecimal(v) },
          "cpv_code"           => Array(notice["main-classification-proc"]).first,
          "location"           => Array(notice["BT-5071-Procedure"]).first,
          "contracting_entity" => {
            "tax_identifier" => buyer_id,
            "name"           => buyer_name,
            "is_public_body" => true
          },
          "winners" => []
        }
      end

      # organisation-name-buyer is {"eng" => ["Name"], ...}. Prefer English,
      # fall back to first available language, then first element of the array.
      def extract_buyer_name(field)
        return "Unknown" unless field.is_a?(Hash)
        names = field["eng"] || field.values.first || []
        Array(names).first.presence || "Unknown"
      end

      # notice-title is {"eng" => "...", "por" => "...", ...}. Prefer English,
      # fall back to Portuguese, then first available language.
      def extract_title(field)
        return nil unless field.is_a?(Hash)
        field["eng"] || field["por"] || field.values.first
      end

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
