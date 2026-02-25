require "simplecov"
SimpleCov.start "rails"

require "minitest/autorun"
$LOAD_PATH.unshift File.expand_path("../../../app/services", __dir__)
require_relative "../../../app/services/public_contracts/pt/registo_comercial"

# Integration test — hits publicacoes.mj.pt live.
# Run with:  bundle exec ruby test/services/public_contracts/registo_comercial_test.rb
class RegistoComercialTest < Minitest::Test
  # NIPC 503970352 — EDP Distribuição SA
  NIPC = "503970352"

  def setup
    @rc = PublicContracts::PT::RegistoComercial.new(pausa: 1)
  end

  def test_pesquisar_por_nipc_validates_format
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("123") }
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("") }
  end

  def test_pesquisar_por_nipc_returns_results_for_503970352
    resultados = @rc.pesquisar_por_nipc(NIPC)

    assert_kind_of Array, resultados
    $stdout.puts "\n  [RegistoComercial] #{resultados.size} publicações para NIPC #{NIPC}"

    unless resultados.empty?
      primeiro = resultados.first
      assert_kind_of Hash, primeiro
      assert primeiro.key?(:resumo), "result should have :resumo key"

      $stdout.puts "  Primeiro resultado:"
      $stdout.puts "    entidade : #{primeiro[:entidade]}"
      $stdout.puts "    data     : #{primeiro[:data]}"
      $stdout.puts "    tipo     : #{primeiro[:tipo]}"
      $stdout.puts "    resumo   : #{primeiro[:resumo]&.slice(0, 120)}"
    end
  end
end
