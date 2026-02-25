# Observatório de Integridade

A Rails 8 application that monitors Portuguese public procurement data to detect corruption risk, abuse patterns, and conflicts of interest. Built for journalists, auditors, and civic watchdogs.

## Overview

The app ingests data from Portal BASE (Portugal's central procurement portal), TED (EU tenders), and auxiliary sources, then scores contracts against a catalogue of red flags derived from OECD, OCP, and Tribunal de Contas methodology.

The approach is **risk scoring, not accusation** — the system surfaces cases for audit or journalistic review, not conclusions.

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

| Source | What it provides | Adapter class |
|---|---|---|
| Portal BASE | Portuguese public contracts (primary) | `PublicContracts::PT::PortalBaseClient` |
| dados.gov.pt | Open data portal, BASE mirrors | `PublicContracts::PT::DadosGovClient` |
| TED | EU-level procurement notices | `PublicContracts::EU::TedClient` |
| Registo Comercial | Company registrations, ownership | `PublicContracts::PT::RegistoComercial` |

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
