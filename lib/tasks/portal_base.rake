# :nocov:
# frozen_string_literal: true

namespace :portal_base do
  namespace :ingest do
    desc "Run full Portal BASE ingestion for all active DataSources"
    task full: :environment do
      page_size = ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i

      if Rails.env.production?
        PortalBase::EnqueueFullIngestionJob.perform_later(page_size: page_size)
        puts "Enqueued full Portal BASE ingestion via Solid Queue (page_size=#{page_size})"
      else
        DataSource.active_sources.portal_base.find_each do |data_source|
          result = PublicContracts::ImportService.new(data_source).call(full: true, page_size: page_size, start_page: 1)
          puts "DataSource ##{data_source.id} imported: fetched=#{result[:fetched]} inserted=#{result[:inserted]} updated=#{result[:updated]} failed=#{result[:failed]}"
        end
      end
    end
  end
end

# :nocov:
