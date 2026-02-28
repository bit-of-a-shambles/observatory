require "test_helper"

class PortalBase::IngestPageJobTest < ActiveJob::TestCase
  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  teardown do
    Rails.cache = @previous_cache
  end
  test "imports page and enqueues next when page is full" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) do |page:, page_size:|
      raise "unexpected page" unless page == 3
      raise "unexpected page size" unless page_size == 10
      { fetched: 10, inserted: 7, updated: 3, failed: 0 }
    end

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_enqueued_with(job: PortalBase::IngestPageJob,
                           args: [ data_source.id, 4, { page_size: 10, run_id: "run-1" } ]) do
        PortalBase::IngestPageJob.perform_now(data_source.id, 3, page_size: 10, run_id: "run-1")
      end
    end
  end

  test "does not enqueue next page when empty" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) { |**_kwargs| { fetched: 0, inserted: 0, updated: 0, failed: 0 } }

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_no_enqueued_jobs only: PortalBase::IngestPageJob do
        PortalBase::IngestPageJob.perform_now(data_source.id, 8, page_size: 10, run_id: "run-1")
      end
    end
  end

  test "transient error does not chain next page" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) do |**_kwargs|
      raise PublicContracts::PT::PortalBaseClient::TransientError, "retry"
    end

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_nothing_raised do
        PortalBase::IngestPageJob.perform_now(data_source.id, 2, page_size: 10, run_id: "run-1")
      end
    end

    chained_job = enqueued_jobs.find do |job|
      job[:job] == PortalBase::IngestPageJob && job[:args].first(2) == [ data_source.id, 3 ]
    end
    assert_nil chained_job
  end

  test "three transient failures open breaker and block fetch while ttl active" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) do |**_kwargs|
      raise PublicContracts::PT::PortalBaseClient::TransientError, "retry"
    end

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      3.times do
        PortalBase::IngestPageJob.perform_now(data_source.id, 1, page_size: 10, run_id: "run-1")
      end
    end

    assert Rails.cache.read("portal_base:ingest:open:#{data_source.id}")

    no_fetch_service = Object.new
    no_fetch_service.define_singleton_method(:call) { |**_kwargs| raise "should not fetch while breaker open" }
    PublicContracts::ImportService.stub(:new, ->(_ds) { no_fetch_service }) do
      assert_raises(PortalBase::IngestPageJob::CircuitOpenError) do
        PortalBase::IngestPageJob.perform_now(data_source.id, 1, page_size: 10, run_id: "run-1")
      end
    end
  end

  test "successful page clears breaker state" do
    data_source = data_sources(:portal_base)
    Rails.cache.write("portal_base:ingest:open:#{data_source.id}", true, expires_in: 15.minutes)
    Rails.cache.write("portal_base:ingest:failures:#{data_source.id}", 3, expires_in: 15.minutes)

    blocker = Object.new
    blocker.define_singleton_method(:call) { |**_kwargs| raise "should not call while open" }
    PublicContracts::ImportService.stub(:new, ->(_ds) { blocker }) do
      assert_raises(PortalBase::IngestPageJob::CircuitOpenError) do
        PortalBase::IngestPageJob.perform_now(data_source.id, 1, page_size: 10, run_id: "run-1")
      end
    end

    Rails.cache.delete("portal_base:ingest:open:#{data_source.id}")

    service = Object.new
    service.define_singleton_method(:call) { |**_kwargs| { fetched: 0, inserted: 0, updated: 0, failed: 0 } }
    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      PortalBase::IngestPageJob.perform_now(data_source.id, 1, page_size: 10, run_id: "run-1")
    end

    assert_nil Rails.cache.read("portal_base:ingest:open:#{data_source.id}")
    assert_nil Rails.cache.read("portal_base:ingest:failures:#{data_source.id}")
  end

  test "stale run is ignored" do
    data_source = data_sources(:portal_base)
    data_source.update!(config: { "portal_base_ingestion" => { "run_id" => "latest-run" } })

    service = Object.new
    service.define_singleton_method(:call) { |**_kwargs| raise "stale run should not call import" }

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_nothing_raised do
        PortalBase::IngestPageJob.perform_now(data_source.id, 1, page_size: 10, run_id: "old-run")
      end
    end

    assert true
  end
end
