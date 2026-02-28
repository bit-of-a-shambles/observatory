# frozen_string_literal: true

module PublicContracts
  module PT
    class PortalBaseClient < PublicContracts::BaseClient
      class TransientError < StandardError; end

      SOURCE_NAME  = "Portal BASE"
      COUNTRY_CODE = "PT"
      BASE_URL     = "http://www.base.gov.pt/api/v1"
      RETRYABLE_STATUS_CODES = [ 429, 500, 502, 503, 504 ].freeze

      def initialize(config = {})
        super(config.fetch("base_url", BASE_URL))
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      def fetch_contracts(page: 1, limit: 50)
        result = get("/contratos", limit: limit, offset: (page - 1) * limit)
        Array(result)
      end

      def find_contract(id)
        get("/contratos/#{id}")
      end

      def get(path, params = {})
        uri = URI("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) if params.any?

        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          handle_error(response)
        end
      rescue TransientError
        raise
      rescue StandardError => e
        Rails.logger.error "[PortalBaseClient] Error: #{e.message}"
        nil
      end

      private

      def handle_error(response)
        if RETRYABLE_STATUS_CODES.include?(response.code.to_i)
          raise TransientError, "Portal BASE retryable status #{response.code}"
        end

        super
      end
    end
  end
end

