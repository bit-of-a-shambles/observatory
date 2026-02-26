require "test_helper"

class PublicContracts::PT::SnsClientTest < ActiveSupport::TestCase
  RECORD = {
    "data_de_celebracao_do_contrato" => "2025-01-15",
    "objeto_do_contrato"             => "Fornecimento de luvas cirúrgicas",
    "tipo_de_procedimento"           => "Ajuste Direto",
    "tipos_de_contrato"              => "Aquisição de bens móveis",
    "cpvs"                           => "33000000-0, Equipamento médico",
    "entidades_adjudicantes_normalizado" => "Centro Hospitalar Lisboa Norte, EPE",
    "nifs_dos_adjudicantes"          => "509186998",
    "entidades_adjudicatarias_normalizado" => "MediSupply Lda",
    "nifs_das_adjudicatarias"        => "509000110",
    "preco_contratual"               => 1500.00,
    "data_de_publicacao"             => "2025-01-20",
    "local_de_execucao"              => "Portugal, Lisboa",
    "preco_total_efetivo"            => 1450.50
  }.freeze

  PAYLOAD = {
    "total_count" => 43261,
    "results"     => [RECORD]
  }.freeze

  def fake_success(body)
    resp = Net::HTTPSuccess.new("1.1", "200", "OK")
    resp.instance_variable_set(:@body, body)
    resp.define_singleton_method(:body) { body }
    resp
  end

  def fake_error(code = "500", message = "Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_| false }
    resp.define_singleton_method(:code)    { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  def mock_http(response)
    mock = Minitest::Mock.new
    mock.expect(:use_ssl=,      nil, [TrueClass])
    mock.expect(:open_timeout=, nil, [Integer])
    mock.expect(:read_timeout=, nil, [Integer])
    mock.expect(:request,       response, [Net::HTTP::Get])
    mock
  end

  setup do
    @client = PublicContracts::PT::SnsClient.new
  end

  test "country_code is PT" do
    assert_equal "PT", @client.country_code
  end

  test "source_name" do
    assert_equal "Portal da Transparência SNS", @client.source_name
  end

  test "fetch_contracts returns array on success" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal 1, result.size
    end
    mock.verify
  end

  test "fetch_contracts returns empty array on HTTP error" do
    mock = mock_http(fake_error)
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
    mock.verify
  end

  test "fetch_contracts returns empty array on exception" do
    raising = Object.new
    raising.define_singleton_method(:use_ssl=)      { |_| }
    raising.define_singleton_method(:open_timeout=) { |_| }
    raising.define_singleton_method(:read_timeout=) { |_| }
    raising.define_singleton_method(:request)       { |_| raise Errno::ECONNREFUSED }
    Net::HTTP.stub(:new, raising) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
  end

  test "normalize maps object field" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal "Fornecimento de luvas cirúrgicas", result.first["object"]
    end
    mock.verify
  end

  test "normalize maps procedure_type" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal "Ajuste Direto", result.first["procedure_type"]
    end
    mock.verify
  end

  test "normalize maps celebration_date as Date" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal Date.new(2025, 1, 15), result.first["celebration_date"]
    end
    mock.verify
  end

  test "normalize maps publication_date" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal Date.new(2025, 1, 20), result.first["publication_date"]
    end
    mock.verify
  end

  test "normalize maps base_price as BigDecimal" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal BigDecimal("1500.0"), result.first["base_price"]
    end
    mock.verify
  end

  test "normalize extracts CPV code from cpvs field" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal "33000000-0", result.first["cpv_code"]
    end
    mock.verify
  end

  test "normalize sets country_code to PT" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal "PT", result.first["country_code"]
    end
    mock.verify
  end

  test "normalize builds contracting_entity with NIF and name" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result   = @client.fetch_contracts
      authority = result.first["contracting_entity"]
      assert_equal "509186998", authority["tax_identifier"]
      assert_equal "Centro Hospitalar Lisboa Norte, EPE", authority["name"]
      assert authority["is_public_body"]
    end
    mock.verify
  end

  test "normalize builds winners array" do
    mock = mock_http(fake_success(PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result  = @client.fetch_contracts
      winners = result.first["winners"]
      assert_equal 1, winners.size
      assert_equal "509000110",  winners.first["tax_identifier"]
      assert_equal "MediSupply Lda", winners.first["name"]
      assert winners.first["is_company"]
    end
    mock.verify
  end

  test "normalize handles pipe-separated multiple winners" do
    multi = RECORD.merge(
      "nifs_das_adjudicatarias"             => "509000110|509000111",
      "entidades_adjudicatarias_normalizado" => "MediSupply Lda|FormaPro Lda"
    )
    payload = { "total_count" => 1, "results" => [multi] }
    mock    = mock_http(fake_success(payload.to_json))
    Net::HTTP.stub(:new, mock) do
      result  = @client.fetch_contracts
      winners = result.first["winners"]
      assert_equal 2, winners.size
      assert_equal "509000110", winners.first["tax_identifier"]
      assert_equal "509000111", winners.last["tax_identifier"]
    end
    mock.verify
  end

  test "generate_id is deterministic for same record" do
    id1 = @client.send(:generate_id, RECORD)
    id2 = @client.send(:generate_id, RECORD)
    assert_equal id1, id2
  end

  test "generate_id differs for different records" do
    other = RECORD.merge("preco_contratual" => 9999.99)
    assert_not_equal @client.send(:generate_id, RECORD),
                     @client.send(:generate_id, other)
  end

  test "total_count queries with limit 0" do
    payload = { "total_count" => 43261, "results" => [] }
    mock    = mock_http(fake_success(payload.to_json))
    Net::HTTP.stub(:new, mock) do
      assert_equal 43261, @client.total_count
    end
    mock.verify
  end

  test "parse_date returns nil for blank" do
    assert_nil @client.send(:parse_date, nil)
    assert_nil @client.send(:parse_date, "")
  end

  test "parse_decimal returns nil for nil" do
    assert_nil @client.send(:parse_decimal, nil)
  end

  test "extract_cpv handles nil" do
    assert_nil @client.send(:extract_cpv, nil)
    assert_nil @client.send(:extract_cpv, "")
  end

  test "accepts page_size from config" do
    client = PublicContracts::PT::SnsClient.new("page_size" => "200")
    assert_instance_of PublicContracts::PT::SnsClient, client
  end
end
