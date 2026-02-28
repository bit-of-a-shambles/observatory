# :nocov:
# frozen_string_literal: true

module PortalBase
  class IngestDataSourceJob < ApplicationJob
    queue_as :portal_base_ingestion

    def perform(data_source_id, page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i, run_id: nil)
      data_source = DataSource.find(data_source_id)
      current_run_id = run_id.presence || SecureRandom.uuid
      start_page = resolve_start_page!(data_source, current_run_id)

      IngestPageJob.perform_later(data_source.id, start_page, page_size: page_size, run_id: current_run_id)
    end

    private

    def resolve_start_page!(data_source, run_id)
      config = data_source.config_hash
      ingestion_state = config.fetch("portal_base_ingestion", {})
      stored_run_id = ingestion_state["run_id"]

      if stored_run_id == run_id
        [ data_source.last_success_page.to_i + 1, 1 ].max
      else
        config["portal_base_ingestion"] = {
          "run_id" => run_id,
          "started_at" => Time.current.iso8601
        }
        data_source.update!(config: config, last_success_page: 0)
        1
      end
    end
  end
end

# :nocov:
