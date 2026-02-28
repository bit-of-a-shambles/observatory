require "test_helper"

class PortalBase::EnqueueFullIngestionJobTest < ActiveJob::TestCase
  test "enqueues one job per active portal base data source and seeds run context" do
    PortalBase::EnqueueFullIngestionJob.perform_now(page_size: 25)

    assert_enqueued_jobs 2, only: PortalBase::IngestDataSourceJob

    DataSource.active_sources.portal_base.find_each do |data_source|
      assert_equal 0, data_source.reload.last_success_page
      assert data_source.config_hash.dig("portal_base_ingestion", "run_id").present?
    end
  end
end
