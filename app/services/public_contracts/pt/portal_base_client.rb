# frozen_string_literal: true

module PublicContracts
  module PT
    class PortalBaseClient < PublicContracts::BaseClient
      SOURCE_NAME  = "Portal BASE"
      COUNTRY_CODE = "PT"
      BASE_URL     = "http://www.base.gov.pt/api/v1"

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
    end
  end
end
