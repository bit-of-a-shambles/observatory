[🇬🇧 English version](README.md)

# Open Tender Watch

Uma aplicação Rails 8 que monitoriza dados de contratação pública em vários países para identificar padrões de risco de corrupção. O resultado são casos para jornalistas e auditores investigarem — não conclusões.

## Visão Geral

A aplicação ingere dados de contratação de fontes nacionais e europeias, cruzando-os contra um catálogo de sinais de alerta derivado da metodologia da OCDE, OCP e Tribunal de Contas.

![Dashboard](screenshot.png)
*Dashboard com contratos sinalizados e pontuações de risco*

![Detalhe do contrato](screenshot_contracts_show.png)
*Página de detalhe — alerta "Celebrado antes da publicação" dispara quando a data de assinatura precede a publicação*

## Arquitetura Internacional

Cada fonte de dados é um registo `DataSource` com `country_code` (ISO 3166-1 alpha-2), `adapter_class` e configuração JSON. O modelo de domínio é delimitado por país:

- A unicidade de `Entity` é `[tax_identifier, country_code]` — o mesmo NIF em PT e ES pertence a entidades distintas.
- A unicidade de `Contract` é `[external_id, country_code]` — IDs numéricos de portais diferentes não colidem.
- O `ImportService` resolve entidades e contratos dentro do contexto de país correto.

Adicionar um novo país requer uma classe adaptadora e um registo na base de dados. Sem alterações ao esquema, sem alterações ao código existente.

## Stack

- Ruby 3.3.0 / Rails 8
- SQLite + Solid Queue
- Hotwire + Tailwind CSS (interface cyberpunk-noir)
- Minitest + SimpleCov (100% de cobertura de linha)

## Instalação

```bash
bundle install
bin/rails db:create db:migrate
bin/dev
```

## Testes

```bash
bundle exec rails test
```

## Fontes de Dados

| País | Fonte | O que fornece | Adaptador |
|---|---|---|---|
| PT | Portal BASE | Portal central de contratos públicos (primário) | `PublicContracts::PT::PortalBaseClient` |
| PT | Portal da Transparência SNS | Contratos do setor da saúde via OpenDataSoft | `PublicContracts::PT::SnsClient` |
| PT | dados.gov.pt | Portal de dados abertos, espelhos BASE e exportações OCDS | `PublicContracts::PT::DadosGovClient` |
| PT | Registo Comercial | Registos de empresas, acionistas e administração | `PublicContracts::PT::RegistoComercial` |
| PT | Entidade Transparência | Entidades públicas, mandatos e pessoas | *(planeado)* |
| EU | TED | Anúncios de contratação europeia em todos os Estados-Membros | `PublicContracts::EU::TedClient` |

## Adicionar um Novo País

1. Crie um adaptador em `app/services/public_contracts/<iso2>/your_client.rb` dentro do módulo `PublicContracts::<ISO2>`.
2. Implemente `fetch_contracts`, `country_code` e `source_name`.
3. Insira um registo `DataSource` apontando para a classe adaptadora.
4. Execute `ImportService.new(data_source).call` para importar.

## Como Funciona a Pontuação

### Camada 1 — Espinha dorsal de contratação

Todos os contratos são normalizados para a mesma estrutura independentemente do país de origem: entidade adjudicante, NIF do fornecedor, tipo de procedimento, código CPV, preços, datas e histórico de alterações.

### Camada 2 — Corroboração externa

A espinha dorsal é cruzada com:
- TED, para verificar consistência de publicação em adjudicações acima dos limiares europeus
- AdC, para comparar NIFs de fornecedores com casos de sanção da Autoridade da Concorrência
- Entidade Transparência, para ligar partes contratuais a pessoas em funções públicas
- Mais Transparência / Portugal 2020, para priorizar contratos com financiamento europeu

### Camada 3 — Duas faixas de pontuação

Uma pontuação composta única é fácil de contornar e difícil de explicar. O sistema executa duas faixas separadamente.

**Faixa A: alertas baseados em regras.** Cada alerta tem uma definição fixa. Se disparar, sabe-se exatamente porquê e pode ser citado numa participação ou reportagem:

| Alerta | Sinal |
|---|---|
| Ajustes diretos repetidos ao mesmo fornecedor | Mesma entidade adjudicante + mesmo fornecedor, 3 ou mais ajustes diretos em 36 meses |
| Execução antes da publicação | `celebration_date` anterior a `publication_date` no BASE |
| Inflação por adendas | Valor da adenda > 20% do preço original do contrato |
| Fracionamento de limiares | Valor do contrato a menos de 5% abaixo de um limiar procedimental |
| Taxa anómala de ajuste direto | Entidade usa ajuste direto muito mais do que pares para o mesmo CPV |
| Execução prolongada | Duração do contrato > 3 anos |
| Anomalia preço/estimativa | `total_effective_price` / `base_price` fora do intervalo esperado |

**Faixa B: alertas por padrão.** Estatísticos, para casos que nenhuma regra isolada deteta:

| Alerta | Sinal |
|---|---|
| Concentração de fornecedores | Um fornecedor obtém quota desproporcionada da despesa de um adjudicante por CPV |
| Rotação de propostas | Fornecedores que surgem juntos mas raramente concorrem de facto |
| Outlier de preço | Preço do contrato > 2σ da distribuição CPV × região × ano |
| Mudança procedimental | Pico no uso de procedimentos excecionais perto do fim do ano fiscal |

Cada caso sinalizado regista os campos que o despoletaram, uma pontuação de completude dos dados e um nível de confiança. NIFs em falta, sequências de datas impossíveis e campos obrigatórios em branco são sinalizados — dados incompletos frequentemente apontam para as mesmas entidades que merecem escrutínio.

## Como Funciona o Pipeline de Dados

Cada fonte de dados é uma classe de serviço Ruby que gere o ciclo ETL completo:

1. **Extração** — obter registos em bruto da fonte (API REST, transferência de ficheiro ou scraping)
2. **Transformação** — converter o payload em bruto num hash de contrato padronizado com nomes de campos consistentes, objetos de data e preços em BigDecimal
3. **Carregamento** — devolver o array; o `ImportService` trata da persistência e da desduplicação de entidades

Todos os adaptadores residem em [app/services/public_contracts/](app/services/public_contracts/) e devem implementar três métodos: `fetch_contracts(page:, limit:)`, `country_code` e `source_name`. O resto da aplicação nunca vê dados em bruto da fonte.

Consulte `AGENTS.md` para o formato completo do hash padronizado, documentação campo a campo e checklist para contribuidores.

## Contribuir

Todos os pull requests são bem-vindos. O backlog do projeto está nos GitHub Issues, organizado por dificuldade e prioridade:

**[Ver issues abertas →](https://github.com/bit-of-a-shambles/open-tender-watch/issues)**

As issues estão etiquetadas por `difficulty: easy / medium / hard`, `type: data / flag / ui / infra` e `priority: now / next / planned`. A etiqueta `good first issue` marca as tarefas mais autónomas para quem está a começar.

### Testes automáticos — GitHub Actions

Todos os pull requests são testados automaticamente pelo GitHub Actions. O workflow corre em cada push e PR para `master`:

```
.github/workflows/ci.yml
```

Executa a suite completa de testes Minitest e impõe **100% de cobertura de linha** via SimpleCov. Um PR não pode ser integrado se o check de cobertura falhar. Não é necessário correr o CI manualmente — basta abrir um PR e o GitHub faz o resto.

Para correr a suite localmente antes de fazer push:

```bash
bundle exec rails test
```

---

### Para programadores

#### Instalação local

Esta é uma aplicação Ruby on Rails 8. Requisitos: Ruby 3.3.0, Bundler, SQLite.

```bash
git clone https://github.com/bit-of-a-shambles/open-tender-watch.git
cd open-tender-watch
bundle install
bin/rails db:create db:migrate db:seed
bin/dev          # inicia Rails + Tailwind watcher
```

A aplicação corre em http://localhost:3000. Não há dependência de Node.js ou npm — o JavaScript é servido via importmaps.

#### Correr os ingestores de dados localmente

Cada fonte de dados tem um adaptador que pode ser executado a partir da consola Rails ou de um script runner.

**Importar de uma fonte específica:**

```bash
# Portal BASE
bin/rails runner "DataSource.find_by(adapter_class: 'PublicContracts::PT::PortalBaseClient').tap { |ds| ImportService.new(ds).call }"

# Contratos SNS (saúde)
bin/rails runner "DataSource.find_by(adapter_class: 'PublicContracts::PT::SnsClient').tap { |ds| ImportService.new(ds).call }"

# TED (anúncios europeus para Portugal)
bin/rails runner "DataSource.find_by(adapter_class: 'PublicContracts::EU::TedClient').tap { |ds| ImportService.new(ds).call }"
```

**Importar todas as fontes ativas:**

```bash
bin/rails runner "DataSource.active_sources.each { |ds| ImportService.new(ds).call }"
```

O adaptador TED requer a variável de ambiente `TED_API_KEY` (registo gratuito em developer.ted.europa.eu). Todas as outras fontes não requerem chave de API.

**Ingestão completa do Portal BASE (todas as DataSources Portal BASE ativas):**

```bash
# Desenvolvimento/teste: corre inline, página a página
bin/rails portal_base:ingest:full PORTAL_BASE_PAGE_SIZE=100

# Produção: enfileira jobs no Solid Queue
bin/rails portal_base:ingest:full PORTAL_BASE_PAGE_SIZE=100
```

Parâmetros operacionais:
- `PORTAL_BASE_PAGE_SIZE` (default `100`)
- `PORTAL_BASE_QUEUE_THREADS` (default `1`, limitado a `2`)
- `PORTAL_BASE_QUEUE_PROCESSES` (default `1`, limitado a `2`)
- `PORTAL_BASE_MAX_RETRIES` (default `5`)
- `PORTAL_BASE_PAGE_SLEEP_SECONDS` (default `0.1`)
- `PORTAL_BASE_CIRCUIT_BREAKER_FAILURE_THRESHOLD` (default `3` falhas consecutivas por DataSource)

Semântica de snapshot:
- A ingestão completa é sempre um snapshot novo (`page=1`).
- `last_success_page` é **apenas para recovery** e só é reutilizado quando o `run_id` ativo coincide.
- Cada execução full enfileirada gera um `run_id` novo por DataSource em `data_sources.config["portal_base_ingestion"]`.

Semântica do circuit breaker:
- O breaker é por DataSource e abre após N falhas transitórias consecutivas.
- O estado aberto tem TTL de 15 minutos.
- A primeira página importada com sucesso limpa automaticamente o estado do breaker.

Progresso e verificação:

```bash
# checkpoints / contagens por DataSource
bin/rails runner "puts DataSource.portal_base.select(:id, :name, :status, :record_count, :last_success_page).map(&:attributes)"

# total de contratos importados de fontes Portal BASE
bin/rails runner "puts Contract.joins(:data_source).where(data_sources: { adapter_class: 'PublicContracts::PT::PortalBaseClient' }).count"
```

#### Adicionar uma nova fonte de dados

1. Criar `app/services/public_contracts/<iso2>/<fonte>_client.rb` dentro do módulo `PublicContracts::<ISO2>`.
2. Implementar `fetch_contracts(page:, limit:)`, `country_code` e `source_name`.
3. `fetch_contracts` deve devolver um array de hashes de contrato padronizados — formato documentado em `AGENTS.md`.
4. Simular todas as chamadas HTTP nos testes; sem pedidos reais na suite. Cobertura deve manter-se a 100%.
5. Adicionar um fixture `DataSource` em `test/fixtures/data_sources.yml`.
6. Adicionar uma linha à tabela de fontes de dados em ambos os ficheiros README e em `AGENTS.md`.

#### Adicionar um sinal de alerta

1. Criar um serviço em `app/services/flags/` que consulta contratos e escreve registos `Flag`.
2. Escrever testes para os casos de disparo e não disparo.
3. Adicionar o alerta ao catálogo em `AGENTS.md`.

---

### Para jornalistas e investigadores

Não é necessário escrever código para contribuir:

- **Assinalar um contrato** — se detetar algo suspeito na interface, abrir uma issue no GitHub com o URL do contrato e o que chamou a atenção.
- **Sugerir uma fonte de dados** — se conhecer um portal de contratação pública ou base de dados de integridade ainda não coberto, abrir uma issue com um link e uma breve descrição.
- **Melhorar o catálogo de alertas** — se conhecer a metodologia da OCDE, do TdC ou da OCP e considerar que falta um indicador ou que um está mal calibrado, abrir uma issue.
- **Testar os dados** — verificar uma amostra de contratos no portal de origem (Portal BASE, TED) e reportar discrepâncias.
- **Traduzir** — os ficheiros de localização estão em `config/locales/`. Um novo idioma é apenas um ficheiro YAML; não é necessário código.

[Abrir uma issue →](https://github.com/bit-of-a-shambles/open-tender-watch/issues/new)

## Roteiro

| Fase | Estado | Âmbito |
|---|---|---|
| 1 — Espinha dorsal de contratação | Em progresso | Ingestão BASE, framework de adaptadores multi-país, modelo de domínio, cobertura de testes >99% |
| 2 — Dashboard baseado em regras | A seguir | Alertas da Faixa A como queries DB, dashboard com filtro de severidade e drill-down de casos |
| 3 — Enriquecimento externo | Planeado | Cruzamento com TED, correspondência de sanções AdC, camada Entidade Transparência |
| 4 — Pontuação por padrões | Planeado | Indicadores estatísticos da Faixa B: índice de concentração, outliers de preço, rotação de propostas |
| 5 — Triagem de casos | Planeado | Pontuação de confiança, trilho de evidências por caso, exportação para referência TdC / AdC / MENAC |
| 6 — Camada de propriedade | Condicionado | Ligação de beneficiário efetivo via RCBE — acesso limitado |


## Documentação

- `AGENTS.md` — modelo de domínio, fontes de dados, catálogo de indicadores, padrão ETL, normas de código
- `DESIGN.md` — sistema de design UI/UX
- `docs/plans/` — planos de implementação e blueprints de investigação
- [GitHub Issues](https://github.com/bit-of-a-shambles/open-tender-watch/issues) — backlog canónico do projeto
