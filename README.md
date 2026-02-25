# Observatório de Integridade

A Rails 8 application that monitors public procurement data across multiple countries to detect corruption risk, abuse patterns, and conflicts of interest. Built for journalists, auditors, and civic watchdogs.

## Overview

The app ingests procurement data from country-specific and EU-wide sources, then scores contracts against a catalogue of red flags derived from OECD, OCP, and Tribunal de Contas methodology.

The approach is **risk scoring, not accusation** — the system surfaces cases for audit or journalistic review, not conclusions.

## International Architecture

Every data source is registered as a `DataSource` record with a `country_code` (ISO 3166-1 alpha-2), an `adapter_class`, and a JSON config blob. The domain model is fully country-scoped:

- `Entity` uniqueness is `[tax_identifier, country_code]` — the same NIF can exist in PT and ES as different entities.
- `Contract` uniqueness is `[external_id, country_code]` — numeric IDs from different portals won't collide.
- `ImportService` resolves entities and contracts within the correct country context.

Adding a new country requires only an adapter class and a database record — no schema changes, no code changes to existing functionality.

## Stack

- Ruby 3.3.0 / Rails 8
- SQLite (development), upgradeable to PostgreSQL
- Hotwire + Tailwind CSS (cyberpunk-noir UI)
- Minitest + SimpleCov (100% line coverage)

## Setup

```bash
bundle install
bin/rails db:create db:migrate
bin/dev
```

## Testing

```bash
bundle exec rails test
```

## Data Sources

| Country | Source | What it provides | Adapter class |
|---|---|---|---|
| PT | Portal BASE | Central public contracts portal (primary) | `PublicContracts::PT::PortalBaseClient` |
| PT | dados.gov.pt | Open data portal, BASE mirrors and OCDS exports | `PublicContracts::PT::DadosGovClient` |
| PT | Registo Comercial | Company registrations, shareholders, management | `PublicContracts::PT::RegistoComercial` |
| PT | Entidade Transparência | Public entities, mandates, and persons | *(planned)* |
| EU | TED | EU-level procurement notices across all member states | `PublicContracts::EU::TedClient` |

Data sources are DB-driven: each `DataSource` record specifies a `country_code`, `adapter_class`, and JSON `config`. Adding a new country means creating a record and writing an adapter that implements `#fetch_contracts`, `#country_code`, and `#source_name`.

## Adding a New Country

1. Create an adapter in `app/services/public_contracts/<iso2>/your_client.rb` inside `PublicContracts::<ISO2>` namespace.
2. Implement the three required methods (`fetch_contracts`, `country_code`, `source_name`).
3. Insert a `DataSource` record pointing to your adapter class.
4. Run `ImportService.new(data_source).call` to ingest.

## Red Flag Catalogue

See `AGENTS.md` for the full indicator catalogue. Priority flags:

1. Repeat direct awards / prior consultations to the same supplier
2. Late publication or execution before publication date
3. Amendment inflation and repeated deadline extensions
4. Supplier concentration by contracting authority and CPV code
5. Price anomalies within same CPV and region
6. Abnormal use of exceptional-procedure types
7. Supplier overlap with AdC (Competition Authority) sanction cases
8. Data quality evasion — missing NIFs, dates, identifiers

## Escalation Routes (Portugal)

| Issue type | Route |
|---|---|
| Financial irregularity, unlawful spending | Tribunal de Contas complaints channel |
| Cartel / bid rigging | Autoridade da Concorrência |
| General corruption / whistleblowing | MENAC reporting channel |

## Docs

- `AGENTS.md` — domain model, data sources, indicator catalogue, coding standards
- `DESIGN.md` — UI/UX design system
- `docs/plans/` — implementation plans
