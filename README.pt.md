[🇬🇧 English version](README.md)

# Observatório de Integridade

Uma aplicação Rails 8 que monitoriza dados de contratação pública em vários países para identificar padrões de risco de corrupção. O resultado são casos para jornalistas e auditores investigarem — não conclusões.

## Visão Geral

A aplicação ingere dados de contratação de fontes nacionais e europeias, cruzando-os contra um catálogo de sinais de alerta derivado da metodologia da OCDE, OCP e Tribunal de Contas.

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
- Minitest + SimpleCov (cobertura de linha próxima de 100%)

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

## Roteiro

| Fase | Estado | Âmbito |
|---|---|---|
| 1 — Espinha dorsal de contratação | Em progresso | Ingestão BASE, framework de adaptadores multi-país, modelo de domínio, cobertura de testes >99% |
| 2 — Dashboard baseado em regras | A seguir | Alertas da Faixa A como queries DB, dashboard com filtro de severidade e drill-down de casos |
| 3 — Enriquecimento externo | Planeado | Cruzamento com TED, correspondência de sanções AdC, camada Entidade Transparência |
| 4 — Pontuação por padrões | Planeado | Indicadores estatísticos da Faixa B: índice de concentração, outliers de preço, rotação de propostas |
| 5 — Triagem de casos | Planeado | Pontuação de confiança, trilho de evidências por caso, exportação para referência TdC / AdC / MENAC |
| 6 — Camada de propriedade | Condicionado | Ligação de beneficiário efetivo via RCBE — acesso limitado |

## Vias de Escalada (Portugal)

| Tipo de questão | Via |
|---|---|
| Irregularidade financeira, despesa ilegal | Canal de denúncia do Tribunal de Contas (aceita denúncias anónimas) |
| Cartel / ajuste de propostas | Autoridade da Concorrência |
| Corrupção geral / denúncia | Canal de reporte do MENAC |

## Documentação

- `AGENTS.md` — modelo de domínio, fontes de dados, catálogo de indicadores, normas de código, to dos
- `DESIGN.md` — sistema de design UI/UX
- `docs/plans/` — planos de implementação e blueprints de investigação
