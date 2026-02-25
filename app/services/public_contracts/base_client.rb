module PublicContracts
  class BaseClient
    require "net/http"
    require "json"

    def initialize(base_url)
      @base_url = base_url
    end

    protected

    def get(path, params = {})
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      
      response = Net::HTTP.get_response(uri)
      
      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        handle_error(response)
      end
    rescue StandardError => e
      Rails.logger.error "[API Client] Error: #{e.message}"
      nil
    end

    def handle_error(response)
      Rails.logger.error "[API Client] Request failed: #{response.code} - #{response.message}"
      nil
    end
  end
end
