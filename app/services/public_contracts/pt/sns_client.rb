# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "digest"

module PublicContracts
  module PT
    #
    # Client for the Portal da Transparência SNS (transparencia.sns.gov.pt).
    #
    # Exposes the same Portal BASE procurement data as a proper JSON API via
    # OpenDataSoft v2.1. No registration or API key required.
    #
    # API docs: https://transparencia.sns.gov.pt/explore/dataset/portal-base/api/
    # Total records (2026-02): ~43,000 (health-sector contracts)
    #
    # OpenDataSoft hard limit: offset + limit ≤ 10,000 per request.
    # Workaround: year-windowed queries — each year has < 10 000 records, so
    # we iterate through years 2010-current plus a pre-2010 bucket and a
    # null-date bucket. The fetch_contracts method maintains internal window
    # state so ImportService#call_all can drive pagination transparently.
    #
    class SnsClient
      SOURCE_NAME  = "Portal da Transparência SNS"
      COUNTRY_CODE = "PT"
      BASE_URL     = "https://transparencia.sns.gov.pt"
      DATASET      = "portal-base"
      RECORDS_URL  = "#{BASE_URL}/api/explore/v2.1/catalog/datasets/#{DATASET}/records"

      # OpenDataSoft records API hard limit is 100 per request.
      MAX_LIMIT = 100

      # Year windows for pagination bypass.  The "pre_2010" and "null_date"
      # synthetic labels are resolved to ODSQL where-clauses in build_windows.
      START_YEAR = 2010

      def initialize(config = {})
        @page_size = [ config.fetch("page_size", MAX_LIMIT).to_i, MAX_LIMIT ].min
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      # Fetches contracts using year-windowed queries to bypass the 10 000-record
      # pagination cap.  Call with page: 1 to (re)start the scroll; subsequent
      # calls continue through the window queue.
      #
      # The page parameter signals intent (1 = start fresh, N = continue) but
      # the actual position is tracked via @sns_window_idx / @sns_window_offset.
      def fetch_contracts(page: 1, limit: MAX_LIMIT)
        if page == 1
          @sns_windows       = build_windows
          @sns_window_idx    = 0
          @sns_window_offset = 0
        end

        effective_limit = [ limit, MAX_LIMIT ].min

        while @sns_window_idx < @sns_windows.length
          where_clause = @sns_windows[@sns_window_idx]
          data         = get_records(limit: effective_limit, offset: @sns_window_offset,
                                     where: where_clause)
          results      = Array(data&.dig("results"))

          if results.empty?
            @sns_window_idx    += 1
            @sns_window_offset  = 0
            next
          end

          @sns_window_offset += results.size
          if results.size < effective_limit
            @sns_window_idx    += 1
            @sns_window_offset  = 0
          end

          return results.filter_map { |r| normalize(r) }
        end

        []
      end

      def total_count
        data = get_records(limit: 0)
        data&.dig("total_count") || 0
      end

      private

      # Ordered list of ODSQL where-clauses covering the full dataset without
      # any single window exceeding 10 000 records.
      def build_windows
        years = (START_YEAR..Date.current.year).map { |y| "year(data_de_publicacao)=#{y}" }
        [ "data_de_publicacao < '#{START_YEAR}-01-01'" ] + years + [ "data_de_publicacao is null" ]
      end

      def get_records(limit:, offset: 0, where: nil)
        uri    = URI(RECORDS_URL)
        params = { limit: limit, offset: offset }
        params[:where] = where if where
        uri.query      = URI.encode_www_form(params)

        http              = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = 15
        http.read_timeout = 60

        request           = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          rails_log("[SnsClient] HTTP #{response.code}: #{response.message}")
          nil
        end
      rescue StandardError => e
        rails_log("[SnsClient] #{e.class}: #{e.message}")
        nil
      end

      def normalize(record)
        {
          "external_id"           => generate_id(record),
          "object"                => record["objeto_do_contrato"].to_s.strip,
          "country_code"          => COUNTRY_CODE,
          "contract_type"         => record["tipos_de_contrato"].to_s.strip,
          "procedure_type"        => record["tipo_de_procedimento"].to_s.strip,
          "publication_date"      => parse_date(record["data_de_publicacao"]),
          "celebration_date"      => parse_date(record["data_de_celebracao_do_contrato"]),
          "base_price"            => parse_decimal(record["preco_contratual"]),
          "total_effective_price" => parse_decimal(record["preco_total_efetivo"]),
          "cpv_code"              => extract_cpv(record["cpvs"]),
          "location"              => record["local_de_execucao"].to_s.strip,
          "contracting_entity"    => build_authority(record),
          "winners"               => build_winners(record)
        }
      end

      def build_authority(record)
        {
          "tax_identifier" => extract_first(record["nifs_dos_adjudicantes"]),
          "name"           => extract_first_name(record["entidades_adjudicantes_normalizado"]),
          "is_public_body" => true
        }
      end

      def build_winners(record)
        nifs  = split_field(record["nifs_das_adjudicatarias"])
        names = split_field(record["entidades_adjudicatarias_normalizado"])

        nifs.zip(names).filter_map do |nif, name|
          next if nif.to_s.strip.empty? && name.to_s.strip.empty?
          {
            "tax_identifier" => nif.to_s.strip,
            "name"           => name.to_s.strip,
            "is_company"     => true
          }
        end
      end

      # Generate a stable external_id from content since the SNS dataset
      # does not expose the Portal BASE idcontrato field directly.
      def generate_id(record)
        Digest::SHA256.hexdigest([
          record["nifs_dos_adjudicantes"].to_s,
          record["nifs_das_adjudicatarias"].to_s,
          record["data_de_celebracao_do_contrato"].to_s,
          record["preco_contratual"].to_s,
          record["objeto_do_contrato"].to_s.slice(0, 60)
        ].join("|"))[0..19]
      end

      # SNS CPV format: "33000000-0, Description text"
      def extract_cpv(value)
        return nil if value.to_s.strip.empty?
        value.to_s.split(",").first.strip
      end

      def split_field(value)
        return [] if value.to_s.strip.empty?
        value.to_s.split("|").map(&:strip).reject(&:empty?)
      end

      def extract_first(value)
        split_field(value).first
      end

      def extract_first_name(value)
        split_field(value).first.to_s.strip
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
