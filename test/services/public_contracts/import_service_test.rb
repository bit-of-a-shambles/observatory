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

  test "call updates mutable contract fields on re-import" do
    external_id = "ext-reimport-1"
    original_attrs = build_contract_attrs(
      "external_id" => external_id,
      "object" => "Serviços de consultoria",
      "procedure_type" => "Ajuste Direto",
      "publication_date" => Date.new(2025, 1, 10),
      "celebration_date" => Date.new(2025, 1, 5),
      "base_price" => 15_000.0,
      "total_effective_price" => 14_500.0,
      "cpv_code" => "79411000",
      "location" => "Lisboa"
    )

    updated_attrs = original_attrs.merge(
      "object" => "Serviços de consultoria (corrigido)",
      "procedure_type" => "Consulta Prévia",
      "publication_date" => Date.new(2025, 1, 12),
      "celebration_date" => Date.new(2025, 1, 8),
      "base_price" => 16_250.0,
      "total_effective_price" => 15_900.0,
      "cpv_code" => "79412000",
      "location" => "Porto"
    )

    with_mocked_adapter([ original_attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
    end

    ds = data_sources(:portal_base)
    adapter2 = Minitest::Mock.new
    adapter2.expect(:fetch_contracts, [ updated_attrs ])
    ds.stub(:adapter, adapter2) do
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
    adapter2.verify

    contract = Contract.find_by!(external_id: external_id, country_code: "PT")
    assert_equal "Serviços de consultoria (corrigido)", contract.object
    assert_equal "Consulta Prévia", contract.procedure_type
    assert_equal Date.new(2025, 1, 12), contract.publication_date
    assert_equal Date.new(2025, 1, 8), contract.celebration_date
    assert_equal BigDecimal("16250.0"), contract.base_price
    assert_equal BigDecimal("15900.0"), contract.total_effective_price
    assert_equal "79412000", contract.cpv_code
    assert_equal "Porto", contract.location
    assert_equal ds.id, contract.data_source_id
    assert_equal Entity.find_by!(tax_identifier: "500000001", country_code: "PT").id, contract.contracting_entity_id
  end

  test "call preserves existing values when re-import payload is sparse" do
    external_id = "ext-reimport-sparse-1"
    original_attrs = build_contract_attrs(
      "external_id" => external_id,
      "object" => "Contrato original",
      "procedure_type" => "Ajuste Direto",
      "publication_date" => Date.new(2025, 2, 1),
      "celebration_date" => Date.new(2025, 1, 28),
      "base_price" => 20_000.0,
      "total_effective_price" => 19_750.0,
      "cpv_code" => "30192000",
      "location" => "Coimbra"
    )

    sparse_attrs = {
      "external_id" => external_id,
      "country_code" => "PT",
      "object" => nil,
      "procedure_type" => "Consulta Prévia",
      "publication_date" => nil,
      "celebration_date" => nil,
      "base_price" => nil,
      "total_effective_price" => nil,
      "cpv_code" => nil,
      "location" => nil,
      "contracting_entity" => original_attrs["contracting_entity"],
      "winners" => original_attrs["winners"]
    }

    with_mocked_adapter([ original_attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
    end

    ds = data_sources(:portal_base)
    adapter2 = Minitest::Mock.new
    adapter2.expect(:fetch_contracts, [ sparse_attrs ])
    ds.stub(:adapter, adapter2) do
      assert_no_difference "Contract.count" do
        PublicContracts::ImportService.new(ds).call
      end
    end
    adapter2.verify

    contract = Contract.find_by!(external_id: external_id, country_code: "PT")
    assert_equal "Contrato original", contract.object
    assert_equal "Consulta Prévia", contract.procedure_type
    assert_equal Date.new(2025, 2, 1), contract.publication_date
    assert_equal Date.new(2025, 1, 28), contract.celebration_date
    assert_equal BigDecimal("20000.0"), contract.base_price
    assert_equal BigDecimal("19750.0"), contract.total_effective_price
    assert_equal "30192000", contract.cpv_code
    assert_equal "Coimbra", contract.location
  end

  test "call ignores blank string updates for mutable text fields" do
    external_id = "ext-reimport-blank-1"
    original_attrs = build_contract_attrs(
      "external_id" => external_id,
      "object" => "Contrato completo",
      "procedure_type" => "Ajuste Direto",
      "cpv_code" => "30200000",
      "location" => "Braga"
    )

    blank_text_attrs = {
      "external_id" => external_id,
      "country_code" => "PT",
      "object" => "",
      "contract_type" => "",
      "procedure_type" => "",
      "cpv_code" => "",
      "location" => "",
      "contracting_entity" => original_attrs["contracting_entity"],
      "winners" => original_attrs["winners"]
    }

    with_mocked_adapter([ original_attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
    end

    ds = data_sources(:portal_base)
    adapter2 = Minitest::Mock.new
    adapter2.expect(:fetch_contracts, [ blank_text_attrs ])
    ds.stub(:adapter, adapter2) do
      PublicContracts::ImportService.new(ds).call
    end
    adapter2.verify

    contract = Contract.find_by!(external_id: external_id, country_code: "PT")
    assert_equal "Contrato completo", contract.object
    assert_equal "Ajuste Direto", contract.procedure_type
    assert_equal "30200000", contract.cpv_code
    assert_equal "Braga", contract.location
  end

  test "call does not overwrite contract when same external_id exists from different data_source" do
    external_id = "shared-id-001"
    original_attrs = build_contract_attrs(
      "external_id" => external_id,
      "object" => "Portal BASE contract",
      "procedure_type" => "Ajuste Direto",
      "base_price" => 11_000.0,
      "cpv_code" => "45200000"
    )

    other_source_attrs = build_contract_attrs(
      "external_id" => external_id,
      "object" => "SNS contract with colliding ID",
      "procedure_type" => "Concurso Público",
      "base_price" => 99_999.0,
      "cpv_code" => "85100000",
      "contracting_entity" => {
        "tax_identifier" => "500000777",
        "name" => "Entidade SNS",
        "is_public_body" => true
      },
      "winners" => [
        { "tax_identifier" => "509999777", "name" => "Fornecedor SNS Lda", "is_company" => true }
      ]
    )

    with_mocked_adapter([ original_attrs ]) do |ds, _|
      PublicContracts::ImportService.new(ds).call
    end

    original_contract = Contract.find_by!(external_id: external_id, country_code: "PT")
    original_data_source_id = original_contract.data_source_id
    original_contracting_entity_id = original_contract.contracting_entity_id
    original_winner_ids = original_contract.winners.pluck(:id)

    sns_ds = data_sources(:sns_pt)
    adapter2 = Minitest::Mock.new
    adapter2.expect(:fetch_contracts, [ other_source_attrs ])
    logged_messages = []
    Rails.logger.stub(:warn, ->(message) { logged_messages << message }) do
      sns_ds.stub(:adapter, adapter2) do
        assert_no_difference "Contract.count" do
          assert_no_difference "Entity.count" do
            PublicContracts::ImportService.new(sns_ds).call
          end
        end
      end
    end
    adapter2.verify

    contract = Contract.find_by!(external_id: external_id, country_code: "PT")
    assert_equal "Portal BASE contract", contract.object
    assert_equal "Ajuste Direto", contract.procedure_type
    assert_equal BigDecimal("11000.0"), contract.base_price
    assert_equal "45200000", contract.cpv_code
    assert_equal original_data_source_id, contract.data_source_id
    assert_equal original_contracting_entity_id, contract.contracting_entity_id
    assert_equal original_winner_ids.sort, contract.winners.pluck(:id).sort
    assert_nil Entity.find_by(tax_identifier: "500000777", country_code: "PT")
    assert_nil Entity.find_by(tax_identifier: "509999777", country_code: "PT")
    assert_equal 1, logged_messages.size
    assert_includes logged_messages.first, "cross-source collision"
    assert_includes logged_messages.first, "external_id=#{external_id}"
    assert_includes logged_messages.first, "existing_data_source_id=#{original_data_source_id}"
    assert_includes logged_messages.first, "incoming_data_source_id=#{sns_ds.id}"
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
