# frozen_string_literal: true

module PublicContracts
  module PT
    class DadosGovClient < PublicContracts::BaseClient
      SOURCE_NAME  = "dados.gov.pt"
      COUNTRY_CODE = "PT"
      BASE_URL     = "https://dados.gov.pt/api/1"

      def initialize(config = {})
        super(config.fetch("base_url", BASE_URL))
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      def fetch_contracts(page: 1, limit: 50)
        result = search_datasets("contratos públicos")
        Array(result&.dig("data"))
      end

      def search_datasets(query)
        get("/datasets", q: query)
      end

      def fetch_resource(resource_id)
        get("/datasets/resources/#{resource_id}")
      end
    end
  end
end
