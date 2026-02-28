require "test_helper"

class PublicContracts::ImportServiceTest < ActiveSupport::TestCase
  FakeAdapter = Struct.new(:pages) do
    def fetch_contracts(page:, limit:)
      _ = limit
      pages.fetch(page, [])
    end
  end

  def build_contract_attrs(overrides = {})
    {
      "external_id" => "ext-#{SecureRandom.hex(4)}",
      "object" => "Serviços de consultoria",
      "country_code" => "PT",
      "contract_type" => "Aquisição de Serviços",
      "procedure_type" => "Ajuste direto",
      "publication_date" => Date.current,
      "base_price" => 15000.0,
      "contracting_entity" => {
        "tax_identifier" => "500000001",
        "name" => "Câmara Municipal Teste",
        "is_public_body" => true
      },
      "winners" => [
        { "tax_identifier" => "509888001", "name" => "Empresa Vencedora Lda", "is_company" => true }
      ]
    }.merge(overrides)
  end

  test "full mode always starts from page 1" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)
    ds.update!(last_success_page: 5)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ], 2 => [] })) do
      result = PublicContracts::ImportService.new(ds).call(full: true, page_size: 10)
      assert_equal 1, result[:start_page]
      assert_equal 1, result[:inserted]
    end
  end

  test "imports one page with bulk upsert and updates counters" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 2 => [ attrs ] })) do
      result = PublicContracts::ImportService.new(ds).call(page: 2, page_size: 10)
      assert_equal 1, result[:fetched]
      assert_equal 1, result[:inserted]
      assert_equal 0, result[:updated]
      assert_equal 0, result[:failed]
    end

    ds.reload
    assert_equal 2, ds.last_success_page
    assert ds.active?
    assert_equal Contract.where(data_source_id: ds.id).count, ds.record_count
  end

  test "importing same page twice is idempotent" do
    attrs = build_contract_attrs("external_id" => "same-contract")
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      assert_no_difference "Contract.count" do
        result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
        assert_equal 0, result[:inserted]
        assert_equal 1, result[:updated]
      end
    end
  end

  test "internal fields are not overwritten by upsert" do
    attrs = build_contract_attrs("external_id" => "protected-contract")
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
    end

    contract = Contract.find_by!(external_id: "protected-contract", country_code: "PT")
    original_created_at = contract.created_at

    sleep 0.01
    updated = attrs.merge("object" => "Novo objeto")
    ds.stub(:adapter, FakeAdapter.new({ 1 => [ updated ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
    end

    contract.reload
    assert_equal original_created_at.to_i, contract.created_at.to_i
    assert_equal "Novo objeto", contract.object
  end

  test "creates contracting entity winner and join row" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_difference "Contract.count", 1 do
        assert_difference "Entity.count", 2 do
          assert_difference "ContractWinner.count", 1 do
            PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
          end
        end
      end
    end
  end

  test "falls back to data source country when payload country missing" do
    attrs = build_contract_attrs.tap { |contract| contract.delete("country_code") }
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
    end

    contract = Contract.find_by!(external_id: attrs["external_id"])
    assert_equal "PT", contract.country_code
  end

  test "skips invalid contracting entity rows" do
    attrs = build_contract_attrs("contracting_entity" => { "tax_identifier" => "", "name" => "" })
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_no_difference "Contract.count" do
        result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
        assert_equal 1, result[:failed]
      end
    end
  end

  test "skips invalid winner rows" do
    attrs = build_contract_attrs("winners" => [ { "tax_identifier" => "", "name" => "No ID" } ])
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_no_difference "ContractWinner.count" do
        PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      end
    end
  end

  test "counts failed contracts and continues page import" do
    valid = build_contract_attrs("external_id" => "ok-1")
    invalid = build_contract_attrs("external_id" => "bad-1", "contracting_entity" => { "tax_identifier" => "", "name" => "" })
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ valid, invalid ] })) do
      result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      assert_equal 2, result[:fetched]
      assert_equal 1, result[:inserted]
      assert_equal 1, result[:failed]
    end
  end

  test "sets status to error when adapter raises" do
    adapter = Object.new
    def adapter.fetch_contracts(page:, limit:)
      _ = page
      _ = limit
      raise RuntimeError, "API down"
    end

    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_raises(RuntimeError) do
        PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      end
    end

    assert ds.reload.error?
  end
end
