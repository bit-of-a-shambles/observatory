require "test_helper"

class PortalBase::IngestDataSourceJobTest < ActiveJob::TestCase
  test "full ingest ignores checkpoint from previous run" do
    data_source = data_sources(:portal_base)
    data_source.update!(
      last_success_page: 7,
      config: { "portal_base_ingestion" => { "run_id" => "old-run-id" } }
    )

    assert_enqueued_with(job: PortalBase::IngestPageJob,
                         args: [ data_source.id, 1, { page_size: 20, run_id: "new-run-id" } ]) do
      PortalBase::IngestDataSourceJob.perform_now(data_source.id, page_size: 20, run_id: "new-run-id")
    end

    assert_equal "new-run-id", data_source.reload.config_hash.dig("portal_base_ingestion", "run_id")
    assert_equal 0, data_source.last_success_page
  end

  test "resume within same run uses checkpoint" do
    data_source = data_sources(:portal_base)
    data_source.update!(
      last_success_page: 4,
      config: { "portal_base_ingestion" => { "run_id" => "same-run" } }
    )

    assert_enqueued_with(job: PortalBase::IngestPageJob,
                         args: [ data_source.id, 5, { page_size: 15, run_id: "same-run" } ]) do
      PortalBase::IngestDataSourceJob.perform_now(data_source.id, page_size: 15, run_id: "same-run")
    end
  end
end
