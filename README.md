# Integrity Observatory

A Rails 8 app that monitors public procurement data across multiple countries to flag corruption risk and abuse patterns. The output is cases for journalists and auditors to investigate, not conclusions.

## Overview

The app ingests procurement data from country-specific and EU-wide sources, then scores contracts against a red flag catalogue derived from OECD, OCP, and Tribunal de Contas methodology.

## International architecture

Each data source is a `DataSource` record with a `country_code` (ISO 3166-1 alpha-2), `adapter_class`, and JSON config. The domain model is scoped per country:

- `Entity` uniqueness is `[tax_identifier, country_code]` — the same NIF number in PT and ES belongs to different entities.
- `Contract` uniqueness is `[external_id, country_code]` — numeric IDs from different portals don't collide.
- `ImportService` resolves entities and contracts within the right country context.

Adding a new country requires an adapter class and a database record. No schema changes, no changes to existing code.

## Stack

- Ruby 3.3.0 / Rails 8
- SQLite
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

## Data sources

| Country | Source | What it provides | Adapter |
|---|---|---|---|
| PT | Portal BASE | Central public contracts portal (primary) | `PublicContracts::PT::PortalBaseClient` |
| PT | dados.gov.pt | Open data portal, BASE mirrors and OCDS exports | `PublicContracts::PT::DadosGovClient` |
| PT | Registo Comercial | Company registrations, shareholders, management | `PublicContracts::PT::RegistoComercial` |
| PT | Entidade Transparência | Public entities, mandates, and persons | *(planned)* |
| EU | TED | EU procurement notices across all member states | `PublicContracts::EU::TedClient` |

Each `DataSource` record specifies a `country_code`, `adapter_class`, and JSON `config`. The adapter must implement `#fetch_contracts`, `#country_code`, and `#source_name`.

## Adding a new country

1. Create an adapter in `app/services/public_contracts/<iso2>/your_client.rb` inside the `PublicContracts::<ISO2>` namespace.
2. Implement `fetch_contracts`, `country_code`, and `source_name`.
3. Insert a `DataSource` record pointing to the adapter class.
4. Run `ImportService.new(data_source).call` to ingest.

## How scoring works

### Layer 1 — Procurement spine

Every contract is normalised to the same structure regardless of source country: authority, supplier NIF, procedure type, CPV code, prices, dates, amendment history.

### Layer 2 — External corroboration

The spine is joined against:
- TED, to check publication consistency for EU-threshold tenders
- AdC, to match supplier NIFs against Portuguese Competition Authority sanction cases
- Entidade Transparência, to link contract parties to persons in public roles
- Mais Transparência / Portugal2020, to prioritise EU-funded contracts

### Layer 3 — Two-track scoring

A single composite score is too easy to game and too hard to explain. Instead the system runs two tracks separately.

**Track A: rule-based flags.** Each flag has a fixed definition. If it fires, you know exactly why and can cite it in a referral or story:

| Flag | Signal |
|---|---|
| Repeat direct awards to same supplier | Same authority + same supplier, 3 or more direct awards within 36 months |
| Execution before publication | `celebration_date` earlier than `publication_date` in BASE |
| Amendment inflation | Amendment value > 20% of original contract price |
| Threshold splitting | Contract value within 5% below a procedural threshold |
| Abnormal direct award rate | Authority uses direct award far more than peers for the same CPV |
| Long execution | Contract duration > 3 years |
| Price-to-estimate anomaly | `total_effective_price` / `base_price` outside the expected range |

**Track B: pattern flags.** Statistical, for cases no single rule catches:

| Flag | Signal |
|---|---|
| Supplier concentration | One supplier takes a disproportionate share of a buyer's spend by CPV |
| Bid rotation | Suppliers who appear together but rarely actually compete |
| Pricing outlier | Contract price > 2σ from CPV × region × year distribution |
| Procedural shift | Spike in exceptional-procedure use near fiscal year end |

Each flagged case records which fields triggered it, a data completeness score, and a confidence level. Missing NIFs, impossible date sequences, and blank mandatory fields are themselves scored as flags — incomplete data often points at the same entities worth scrutinising.

See `AGENTS.md` for the full catalogue with OECD and OCP methodology references.

## Roadmap

| Phase | Status | Scope |
|---|---|---|
| 1 — Procurement spine | Done | BASE ingestion, multi-country adapter framework, domain model, 100% test coverage |
| 2 — Rule-based dashboard | Next | Track A flags as DB queries, dashboard with severity filter and case drill-down |
| 3 — External enrichment | Planned | TED cross-checking, AdC sanction matching, Entidade Transparência layer |
| 4 — Pattern scoring | Planned | Track B statistical indicators: concentration index, pricing outliers, bid rotation |
| 5 — Case triage | Planned | Confidence scoring, evidence trail per case, export for TdC / AdC / MENAC referral |
| 6 — Ownership layer | Constrained | RCBE beneficial ownership linkage — access is limited by the 2022 CJEU ruling |

## Escalation routes (Portugal)

| Issue type | Route |
|---|---|
| Financial irregularity, unlawful spending | Tribunal de Contas complaints channel (anonymous accepted) |
| Cartel / bid rigging | Autoridade da Concorrência |
| General corruption / whistleblowing | MENAC reporting channel |

## Docs

- `AGENTS.md` — domain model, data sources, indicator catalogue, coding standards
- `DESIGN.md` — UI/UX design system
- `docs/plans/` — implementation plans and research blueprints
