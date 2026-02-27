# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PublicContracts
  module PT
    #
    # Client for quemfatura.pt — a Portuguese public procurement portal that
    # aggregates data from Portal BASE. 23,503+ contracts.
    #
    # List API:   GET /api/contracts?skip=<offset>&limit=<n>
    #   Response: { total_count:, skip:, limit:, contracts: [...] }
    #   Fields:   idcontrato, objectoContrato, precoContratual, dataPublicacao,
    #             adjudicante, adjudicatarios, adjudicante_ids, adjudicatario_ids,
    #             adjudicante_nomes, adjudicatario_nomes, tipoprocedimento
    #
    # Detail API: GET /api/contracts/:id
    #   Adds:     dataCelebracaoContrato, prazoExecucao, localExecucao,
    #             fundamentacao, cpvs, dataDecisaoAdjudicacao, dataFechoContrato
    #
    # The site uses Cloudflare Managed Challenge. Requests require a valid
    # cf_clearance cookie, which must be obtained from a real browser session
    # and stored in the DataSource config as "cf_clearance".
    #
    # Config keys:
    #   "cf_clearance"  — Cloudflare clearance cookie value (required for live requests)
    #   "page_size"     — records per request (default/max: 100)
    #   "fetch_details" — when true, fetches the detail endpoint for each contract
    #                     to populate celebration_date, location, cpv_code (default: false)
    #
    class QuemFaturaClient
      SOURCE_NAME  = "QuemFatura.pt"
      COUNTRY_CODE = "PT"
      BASE_URL     = "https://quemfatura.pt"
      CONTRACTS_URL = "#{BASE_URL}/api/contracts"

      MAX_LIMIT = 100

      DEFAULT_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:140.0) Gecko/20100101 Firefox/140.0"

      def initialize(config = {})
        @cf_clearance  = config.fetch("cf_clearance", nil)
        @user_agent    = config.fetch("user_agent", DEFAULT_USER_AGENT)
        @page_size     = [ config.fetch("page_size", MAX_LIMIT).to_i, MAX_LIMIT ].min
        @fetch_details = config.fetch("fetch_details", false)
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      def total_count
        data = fetch_page(skip: 0, limit: 1)
        data&.dig("total_count") || 0
      end

      def fetch_contracts(page: 1, limit: MAX_LIMIT)
        effective_limit = [ limit, MAX_LIMIT ].min
        skip            = (page - 1) * effective_limit
        data            = fetch_page(skip: skip, limit: effective_limit)
        return [] unless data

        Array(data["contracts"]).map do |c|
          raw = @fetch_details ? fetch_contract_detail(c) : c
          normalize(raw)
        end
      end

      # Fetches the full detail record for a single contract and merges it with
      # the summary record.  Returns the summary unchanged if the detail fetch fails.
      def fetch_contract_detail(contract_summary)
        id     = contract_summary["idcontrato"]
        return contract_summary unless id

        detail = fetch_json("#{CONTRACTS_URL}/#{id}")
        detail ? contract_summary.merge(detail) : contract_summary
      end

      private

      def fetch_page(skip:, limit:)
        uri       = URI(CONTRACTS_URL)
        uri.query = URI.encode_www_form(skip: skip, limit: limit)
        fetch_json(uri.to_s)
      end

      def fetch_json(url)
        uri               = URI(url)
        http              = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = 15
        http.read_timeout = 60

        request                  = Net::HTTP::Get.new(uri)
        request["Accept"]        = "application/json"
        request["User-Agent"]    = @user_agent
        request["Referer"]       = "#{BASE_URL}/contracts"
        request["Cookie"]        = "cf_clearance=#{@cf_clearance}" if @cf_clearance

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          rails_log("[QuemFaturaClient] HTTP #{response.code}: #{response.message}")
          nil
        end
      rescue StandardError => e
        rails_log("[QuemFaturaClient] #{e.class}: #{e.message}")
        nil
      end

      def normalize(contract)
        {
          "external_id"        => contract["idcontrato"].to_s,
          "object"             => contract["objectoContrato"].to_s.strip,
          "country_code"       => COUNTRY_CODE,
          "procedure_type"     => contract["tipoprocedimento"].to_s.strip,
          "publication_date"   => parse_date(contract["dataPublicacao"]),
          "celebration_date"   => parse_date(contract["dataCelebracaoContrato"]),
          "base_price"         => parse_decimal(contract["precoContratual"]),
          "cpv_code"           => extract_cpv(contract["cpvs"]),
          "location"           => contract["localExecucao"].to_s.strip.presence,
          "contracting_entity" => build_authority(contract),
          "winners"            => build_winners(contract)
        }
      end

      def build_authority(contract)
        nif  = Array(contract["adjudicante"]).first.to_s.strip
        name = Array(contract["adjudicante_nomes"]).first.to_s.strip
        { "tax_identifier" => nif, "name" => name, "is_public_body" => true }
      end

      def build_winners(contract)
        nifs  = Array(contract["adjudicatarios"]).map { |v| v.to_s.strip }
        names = Array(contract["adjudicatario_nomes"]).map { |v| v.to_s.strip }

        nifs.zip(names).filter_map do |nif, name|
          next if nif.empty? && name.to_s.empty?
          { "tax_identifier" => nif, "name" => name.to_s, "is_company" => true }
        end
      end

      # QuemFatura CPV format: "33000000-0" or "33000000-0 - Description"
      def extract_cpv(value)
        return nil if value.to_s.strip.empty?
        value.to_s.split(/[\s-]/, 2).first.strip
      end

      def parse_date(value)
        return nil if value.to_s.strip.empty?
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def parse_decimal(value)
        return nil if value.nil?
        BigDecimal(value.to_s)
      rescue ArgumentError, TypeError
        nil
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
