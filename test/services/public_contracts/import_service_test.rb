require "test_helper"

class PublicContracts::ImportServiceTest < ActiveSupport::TestCase
  def build_contract_attrs(overrides = {})
    {
      "external_id"   => "ext-#{SecureRandom.hex(4)}",
      "object"        => "Serviços de consultoria",
      "country_code"  => "PT",
      "contract_type" => "Aquisição de Serviços",
      "base_price"    => 15000.0,
      "contracting_entity" => {
        "tax_identifier" => "500000001",
        "name"           => "Câmara Municipal Teste",
        "is_public_body" => true
      },
      "winners" => [
        { "tax_identifier" => "509888001", "name" => "Empresa Vencedora Lda", "is_company" => true }
      ]
    }.merge(overrides)
  end

  def with_mocked_adapter(contracts)
    adapter = Minitest::Mock.new
    adapter.expect(:fetch_contracts, contracts)
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      yield ds, adapter
    end
    adapter.verify
  end

  # ── happy path ────────────────────────────────────────────────────────────

  test "call creates a contract from adapter data" do
    attrs = build_contract_attrs
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_difference "Contract.count", 1 do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call creates the contracting entity" do
    attrs = build_contract_attrs
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_difference "Entity.count", 2 do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call creates winner entity and contract_winner" do
    attrs = build_contract_attrs
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_difference "ContractWinner.count", 1 do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call sets data_source on contract" do
    attrs = build_contract_attrs
    with_mocked_adapter([ attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
      contract = Contract.find_by(external_id: attrs["external_id"])
      assert_equal ds.id, contract.data_source_id
    end
  end

  test "call sets country_code from attrs" do
    attrs = build_contract_attrs("country_code" => "PT")
    with_mocked_adapter([ attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
      contract = Contract.find_by(external_id: attrs["external_id"])
      assert_equal "PT", contract.country_code
    end
  end

  test "call falls back to data_source country_code when attrs has none" do
    attrs = build_contract_attrs.tap { |a| a.delete("country_code") }
    with_mocked_adapter([ attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
      contract = Contract.find_by(external_id: attrs["external_id"])
      assert_equal ds.country_code, contract.country_code
    end
  end

  test "call sets status to active and updates last_synced_at" do
    with_mocked_adapter([]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
      ds.reload
      assert ds.active?
      assert_not_nil ds.last_synced_at
    end
  end

  test "call updates record_count" do
    attrs1 = build_contract_attrs
    attrs2 = build_contract_attrs
    with_mocked_adapter([ attrs1, attrs2 ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
      assert_equal 2, ds.reload.record_count
    end
  end

  test "call is idempotent for same external_id" do
    attrs = build_contract_attrs
    with_mocked_adapter([ attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
    end
    adapter2 = Minitest::Mock.new
    adapter2.expect(:fetch_contracts, [ attrs ])
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter2) do
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
    adapter2.verify
  end

  test "call skips contract when object is blank" do
    attrs = build_contract_attrs("object" => "")
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call skips contract when contracting_entity has blank tax_id" do
    attrs = build_contract_attrs(
      "contracting_entity" => { "tax_identifier" => "", "name" => "X" }
    )
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call skips contract when contracting_entity has blank name" do
    attrs = build_contract_attrs(
      "contracting_entity" => { "tax_identifier" => "123456789", "name" => "" }
    )
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  test "call skips winner with blank tax_id" do
    attrs = build_contract_attrs(
      "winners" => [ { "tax_identifier" => "", "name" => "X" } ]
    )
    with_mocked_adapter([ attrs ]) do |ds, _|
      assert_no_difference "ContractWinner.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
  end

  # ── call_all ───────────────────────────────────────────────────────────────

  test "call_all paginates until adapter returns empty batch" do
    attrs = build_contract_attrs
    adapter = Object.new
    call_count = 0
    adapter.define_singleton_method(:total_count) { 1 }
    adapter.define_singleton_method(:fetch_contracts) do |page: 1, limit: 100|
      call_count += 1
      call_count == 1 ? [ attrs ] : []
    end
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_difference "Contract.count", 1 do
        PublicContracts::ImportService.new(ds).call_all(progress: nil)
      end
      assert_equal 1, ds.reload.record_count
      assert ds.active?
    end
  end

  test "call_all prints progress when progress object and total_count are provided" do
    attrs = build_contract_attrs
    adapter = Object.new
    call_count = 0
    adapter.define_singleton_method(:total_count) { 1 }
    adapter.define_singleton_method(:fetch_contracts) do |page: 1, limit: 100|
      call_count += 1
      call_count == 1 ? [ attrs ] : []
    end
    progress = StringIO.new
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      PublicContracts::ImportService.new(ds).call_all(progress: progress)
    end
    assert_match(/imported/, progress.string)
    assert_match(/Done/, progress.string)
  end

  test "call_all sleeps between pages when adapter responds to inter_page_delay" do
    attrs = build_contract_attrs
    adapter = Object.new
    call_count = 0
    adapter.define_singleton_method(:total_count)      { 1 }
    adapter.define_singleton_method(:inter_page_delay) { 0 }
    adapter.define_singleton_method(:fetch_contracts) do |page: 1, limit: 100|
      call_count += 1
      call_count == 1 ? [ attrs ] : []
    end
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_difference "Contract.count", 1 do
        PublicContracts::ImportService.new(ds).call_all(progress: nil)
      end
    end
  end

  test "call_all sets status to error when adapter raises" do
    adapter = Object.new
    adapter.define_singleton_method(:total_count) { raise RuntimeError, "boom" }
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_raises(RuntimeError) do
        PublicContracts::ImportService.new(ds).call_all(progress: nil)
      end
    end
    assert ds.reload.error?
  end

  # ── error handling ─────────────────────────────────────────────────────────

  test "call sets status to error when adapter raises" do
    adapter = Minitest::Mock.new
    adapter.expect(:fetch_contracts, nil) { raise RuntimeError, "API down" }
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_raises(RuntimeError) do
        PublicContracts::ImportService.new(ds).call
      end
    end
    assert ds.reload.error?
  end
end
