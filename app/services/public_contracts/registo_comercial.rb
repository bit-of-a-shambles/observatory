#!/usr/bin/env ruby
# frozen_string_literal: true

#
# CLI shim — loads the namespaced class and re-exports as top-level constants
# for backward-compatible standalone use:
#   ruby app/services/public_contracts/registo_comercial.rb NIPC
#
require_relative "pt/registo_comercial"

RegistoComercial = PublicContracts::PT::RegistoComercial unless defined?(RegistoComercial)
ConsultaEmLote   = PublicContracts::PT::ConsultaEmLote   unless defined?(ConsultaEmLote)
Cruzamento       = PublicContracts::PT::Cruzamento       unless defined?(Cruzamento)

# :nocov:
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts <<~AJUDA
      ╔══════════════════════════════════════════════════════╗
      ║  Registo Comercial — Consulta de Atos Societários   ║
      ║  Fonte: publicacoes.mj.pt (Ministério da Justiça)   ║
      ╚══════════════════════════════════════════════════════╝

      Utilização:
        ruby registo_comercial.rb NIPC              # pesquisa singular
        ruby registo_comercial.rb "Nome da Empresa"  # pesquisa por nome
        ruby registo_comercial.rb --lote FICHEIRO.csv # pesquisa em lote
        ruby registo_comercial.rb --cruzar BASE.csv REGISTO.json

      Exemplos:
        ruby registo_comercial.rb 509999001
        ruby registo_comercial.rb "TAP Air Portugal"
        ruby registo_comercial.rb --lote dados_base/resultado.csv

      O ficheiro CSV deve ter uma coluna com NIPC (detectada automaticamente).
      Os resultados são gravados em resultados_registo.json.
    AJUDA
    exit
  end

  if ARGV[0] == "--lote"
    ficheiro = ARGV[1] || "dados_base/resultado.csv"
    abort "Ficheiro não encontrado: #{ficheiro}" unless File.exist?(ficheiro)

    lote = ConsultaEmLote.new(ficheiro_csv: ficheiro)
    lote.executar

  elsif ARGV[0] == "--cruzar"
    base = ARGV[1] || "dados_base/resultado.csv"
    registo = ARGV[2] || "resultados_registo.json"
    abort "Ficheiro não encontrado: #{base}" unless File.exist?(base)
    abort "Ficheiro não encontrado: #{registo}" unless File.exist?(registo)

    cruz = Cruzamento.new(ficheiro_base: base, ficheiro_registo: registo)
    cruz.detectar_ligacoes

  else
    consulta = ARGV[0]
    rc = RegistoComercial.new

    if consulta.match?(/^\d{9}$/)
      puts "A pesquisar NIPC #{consulta}...\n"
      pubs = rc.investigar(consulta)
    else
      puts "A pesquisar '#{consulta}'...\n"
      pubs = rc.pesquisar_por_nome(consulta)
    end

    if pubs.empty?
      puts "Sem resultados."
    else
      puts "\n#{pubs.size} publicações encontradas:\n"
      pubs.each_with_index do |pub, i|
        puts "#{i + 1}. #{pub[:resumo]}"
        if pub[:detalhe]
          d = pub[:detalhe]
          puts "   Entidade: #{d[:entidade]}" if d[:entidade]
          puts "   Capital:  #{d[:capital_social]}" if d[:capital_social]
          puts "   Sede:     #{d[:sede]}" if d[:sede]
          puts "   Sócios:   #{d[:socios].join(', ')}" if d[:socios]&.any?
          puts "   Gerentes: #{d[:gerentes].join(', ')}" if d[:gerentes]&.any?
        end
        puts
      end

      # Gravar em JSON
      File.write("resultado_#{consulta.gsub(/\W/, '_')}.json", JSON.pretty_generate(pubs))
      puts "✓ Resultados gravados"
    end
  end
end
# :nocov:
