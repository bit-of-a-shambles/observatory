# Integrity Observatory

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

## How Scoring Works

The system uses a **three-layer architecture** to turn raw procurement data into actionable intelligence.

### Layer 1 — Procurement spine

Every contract is normalised into a common structure regardless of source country: authority, supplier NIF, procedure type, CPV code, prices, dates, amendment history. This is the foundation everything else is built on.

### Layer 2 — External corroboration

The spine is enriched with cross-source data:
- **TED** — cross-checks publication consistency for EU-threshold tenders
- **AdC** — matches supplier NIFs against Portuguese Competition Authority sanction cases
- **Entidade Transparência** — links contract parties to persons in public roles, surfacing potential conflicts of interest
- **Mais Transparência / Portugal2020** — flags EU-funded contracts for priority scrutiny

### Layer 3 — Two-track scoring

A single composite score is not enough — it obscures reasoning and is hard to audit. Instead the system runs two parallel tracks:

**Track A: Rule-based red flags** — deterministic, fully explainable, ready for media use.

Each flag has a clear definition and can be cited directly in a story or referral:

| Flag | Signal |
|---|---|
| Repeat direct awards to same supplier | Same authority → same supplier, ≥ 3 direct awards within 36 months |
| Execution before publication | `celebration_date` earlier than `publication_date` in BASE |
| Amendment inflation | Amendment value > 20% of original contract price |
| Threshold splitting | Contract value within 5% below a procedural threshold |
| Buyer above peer median for direct awards | Authority uses direct award far more than peers for same CPV |
| Long execution | Contract duration > 3 years |
| Price-to-estimate anomaly | `total_effective_price` / `base_price` outside expected range |

**Track B: Pattern-based anomaly flags** — statistical, for cases no single rule can catch.

| Flag | Signal |
|---|---|
| Supplier concentration | One supplier holds disproportionate share of a buyer's spend by CPV |
| Bid rotation | Set of suppliers who appear together but rarely compete |
| Pricing outlier | Contract price > 2σ from CPV × region × year distribution |
| Procedural shift | Sudden increase in exceptional procedures near fiscal year end |

Every flagged case is tagged with its **evidence fields**, a **data completeness score**, and an explicit **confidence level** (low / medium / high) — so weak data never produces overconfident conclusions. Missingness is itself a signal: missing NIFs, impossible date sequences, and incomplete mandatory fields are scored as data-quality red flags.

See `AGENTS.md` for the full indicator catalogue with OECD and OCP methodology references.

## Roadmap

| Phase | Status | Scope |
|---|---|---|
| **1 — Procurement spine** | ✅ Done | BASE ingestion pipeline, multi-country adapter framework, domain model, 100% test coverage |
| **2 — Rule-based dashboard** | 🔜 Next | Track A red flags implemented as DB queries, dashboard with severity filter and case drill-down |
| **3 — External enrichment** | Planned | TED cross-checking, AdC sanction matching, Entidade Transparência conflict-of-interest layer |
| **4 — Pattern scoring** | Planned | Track B statistical indicators: concentration index, pricing outliers, bid rotation detection |
| **5 — Case triage** | Planned | Confidence scoring, evidence trail per case, export for referral to TdC / AdC / MENAC |
| **6 — Ownership layer** | Constrained | RCBE beneficial ownership linkage — access limited by CJEU ruling; treat as best-effort |

## Escalation Routes (Portugal)

| Issue type | Route |
|---|---|
| Financial irregularity, unlawful spending | Tribunal de Contas complaints channel (anonymous accepted) |
| Cartel / bid rigging | Autoridade da Concorrência |
| General corruption / whistleblowing | MENAC reporting channel |

## Docs

- `AGENTS.md` — domain model, data sources, full indicator catalogue, coding standards
- `DESIGN.md` — UI/UX design system
- `docs/plans/` — implementation plans and research blueprints
