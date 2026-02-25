require "test_helper"
require_relative "../../../support/registo_comercial_fixtures"

class PublicContracts::PT::RegistoComercialTest < ActiveSupport::TestCase
  include RegistoComercialFixtures

  setup do
    @rc = PublicContracts::PT::RegistoComercial.new(pausa: 0)
  end

  # ── NIPC validation ────────────────────────────────────────────────────────
  test "pesquisar_por_nipc raises on short NIPC" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("123") }
  end

  test "pesquisar_por_nipc raises on empty string" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("") }
  end

  test "pesquisar_por_nipc strips non-digits before length check" do
    @rc.stub(:pesquisar, []) do
      result = @rc.pesquisar_por_nipc("123-456-789")
      assert_equal [], result
    end
  end

  test "pesquisar_por_nome raises on empty name" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nome("") }
  end

  test "pesquisar_por_nome raises on blank name" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nome("   ") }
  end

  # ── extrair_campos_ocultos ─────────────────────────────────────────────────
  test "extrair_campos_ocultos returns hash of hidden inputs" do
    campos = @rc.send(:extrair_campos_ocultos, HIDDEN_FIELDS_HTML)
    assert_equal "abc123", campos["__VIEWSTATE"]
    assert_equal "xyz789", campos["__EVENTVALIDATION"]
  end

  # ── extrair_resultados ─────────────────────────────────────────────────────
  test "extrair_resultados parses table rows" do
    results = @rc.send(:extrair_resultados, SEARCH_RESULTS_HTML)
    assert_equal 2, results.size
    assert_equal "509999001", results.first[:nipc]
    assert_equal "Construções Ferreira Lda", results.first[:entidade]
    assert results.first[:ligacao].include?("DetalhePublicacao")
  end

  test "extrair_resultados falls back to GridView selector" do
    results = @rc.send(:extrair_resultados, GRIDVIEW_HTML)
    assert results.size >= 1
  end

  test "extrair_resultados falls back to link scan when no table rows" do
    results = @rc.send(:extrair_resultados, FALLBACK_LINKS_HTML)
    assert results.size >= 1
    assert results.first[:ligacao].include?("Detalhe")
  end

  test "extrair_resultados skips all-empty rows" do
    results = @rc.send(:extrair_resultados, EMPTY_ROWS_HTML)
    assert_equal 0, results.size
  end

  # ── postback links ─────────────────────────────────────────────────────────
  test "extrair_linha_resultado marks postback links as :postback" do
    results = @rc.send(:extrair_resultados, POSTBACK_HTML)
    assert_equal 1, results.size
    assert_equal :postback, results.first[:ligacao]
  end

  # ── extrair_detalhe ────────────────────────────────────────────────────────
  test "extrair_detalhe parses NIPC" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "509999001", detalhe[:nipc]
  end

  test "extrair_detalhe parses entidade" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "Construções Ferreira Lda", detalhe[:entidade]
  end

  test "extrair_detalhe parses sede" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "Rua das Obras 10, Porto", detalhe[:sede]
  end

  test "extrair_detalhe parses capital_social" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "50.000 EUR", detalhe[:capital_social]
  end

  test "extrair_detalhe parses natureza_juridica" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "Sociedade por Quotas", detalhe[:natureza_juridica]
  end

  test "extrair_detalhe extracts socios from lblConteudo" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_includes detalhe[:socios], "João Ferreira"
  end

  test "extrair_detalhe extracts gerentes from lblConteudo" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_includes detalhe[:gerentes], "Maria Silva"
  end

  test "extrair_detalhe uses fallback for corpo" do
    detalhe = @rc.send(:extrair_detalhe, CORPO_FALLBACK_HTML)
    refute_nil detalhe[:corpo]
  end

  test "extrair_detalhe returns hash for empty HTML" do
    detalhe = @rc.send(:extrair_detalhe, "<html></html>")
    assert_kind_of Hash, detalhe
  end

  # ── text extraction ────────────────────────────────────────────────────────
  test "extrair_socios finds name after socio pattern" do
    texto = "Sócios: António Rodrigues, NIF 111222333, com 100%."
    nomes = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "António Rodrigues"
  end

  test "extrair_socios finds quota pattern" do
    texto = "quota pertencente a Carlos Mendes com 50%"
    nomes = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "Carlos Mendes"
  end

  test "extrair_socios finds accionista pattern" do
    texto = "Accionistas: Sofia Pinto, detendo 1000 acções"
    nomes = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "Sofia Pinto"
  end

  test "extrair_socios returns unique names" do
    texto = "Sócios: Manuel Costa, NIF 123. Sócios: Manuel Costa, NIF 123."
    nomes = @rc.send(:extrair_socios, texto)
    assert_equal 1, nomes.count { |n| n == "Manuel Costa" }
  end

  test "extrair_gerentes finds gerente pattern" do
    texto = "Gerentes: Rui Alves, residente em Lisboa."
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Rui Alves"
  end

  test "extrair_gerentes finds administrador pattern" do
    texto = "Administradores: Pedro Gomes, portador do BI 12345"
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Pedro Gomes"
  end

  test "extrair_gerentes finds presidente pattern" do
    texto = "Presidente: Lúcia Faria com funções de gestão"
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Lúcia Faria"
  end

  test "extrair_gerentes returns unique names" do
    texto = "Gerentes: Rui Alves. Gerentes: Rui Alves."
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_equal 1, nomes.count { |n| n == "Rui Alves" }
  end

  # ── obter_detalhe guards ───────────────────────────────────────────────────
  test "obter_detalhe returns nil for nil" do
    assert_nil @rc.obter_detalhe(nil)
  end

  test "obter_detalhe returns nil for non-http link" do
    assert_nil @rc.obter_detalhe("javascript:void(0)")
  end
end
