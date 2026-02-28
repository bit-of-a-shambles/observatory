# :nocov:
# frozen_string_literal: true

module PortalBase
  class EnqueueFullIngestionJob < ApplicationJob
    queue_as :portal_base_ingestion

    def perform(page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i)
      DataSource.active_sources.portal_base.find_each do |data_source|
        run_id = SecureRandom.uuid
        persist_run_context!(data_source, run_id)
        IngestDataSourceJob.perform_later(data_source.id, run_id: run_id, page_size: page_size)
      end
    end

    private

    def persist_run_context!(data_source, run_id)
      config = data_source.config_hash
      config["portal_base_ingestion"] = {
        "run_id" => run_id,
        "started_at" => Time.current.iso8601
      }

      data_source.update!(config: config, last_success_page: 0)
    end
  end
end

# :nocov:
