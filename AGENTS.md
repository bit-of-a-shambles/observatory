# Observatório de Integridade — Context & Guidelines

## Project Overview

The **Observatório de Integridade** is a Rails 8 application that monitors Portuguese (and broader European) public procurement data to detect corruption risk, abuse patterns, and conflicts of interest. It is designed for journalists, auditors, and civic watchdogs.

The approach is **risk scoring, not accusation**. The system surfaces cases for audit or journalistic review with explicit confidence levels — it does not produce conclusions.

---

## Domain Model

- **Entity**: Represents both public bodies (adjudicantes) and private companies (adjudicatários). Identified by `tax_identifier` (NIF/NIPC), scoped to `country_code` — the same numeric ID can exist in different countries.
- **Contract**: A public procurement record with metadata (object, price, dates, procedure type, CPV, location). Linked to a contracting entity and a data source.
- **ContractWinner**: Join table between `Contract` and `Entity`. A contract can have multiple winners with a `price_share`.
- **DataSource**: DB-driven registry of configured data adapters per country. Each record specifies `adapter_class`, `country_code`, `source_type`, and JSON `config`.

---

## Key Data Sources

### Portugal

| Source | What it provides | Notes |
|---|---|---|
| **Portal BASE** | Central public contracts portal — contracts, announcements, modifications, impugnations | Primary source. Data published in OCDS format on dados.gov.pt via IMPIC. API access available for bulk extraction (registration required). Data quality is the responsibility of contracting entities — late or incomplete entries are themselves risk signals. |
| **dados.gov.pt** | Open data platform, includes BASE mirrors | Use for bulk OCDS downloads |
| **TED** | EU-level procurement notices | Valuable for contracts at EU thresholds and cross-checking publication consistency |
| **Registo Comercial** | Company registrations, shareholders, management | Scraped from publicacoes.mj.pt |
| **RCBE** | Beneficial ownership register | Access requires authentication by legal person number; CJEU ruling limited open access — treat as a constrained layer |
| **AdC** | Competition Authority — cartel cases, sanctions | Cross-reference supplier NIFs against published AdC cases |
| **Tribunal de Contas** | Audit reports, financial liability decisions | Used to corroborate red flags |
| **Mais Transparência / Portugal2020** | EU-funded contract data | Useful for prioritising EU-funded tenders |
| **ECFP/CNE** | Political party donations | Future source for conflict-of-interest detection |

### EU / Cross-border

| Source | What it provides |
|---|---|
| **TED** | EU procurement notices via REST API and bulk XML packages |

---

## Red Flag Catalogue

Indicators are grouped into three tracks following OECD methodology:

### Track A — Rule-based red flags (high explainability)

| # | Indicator | Data fields | Notes |
|---|---|---|---|
| A1 | Repeat direct awards / prior consultations to same supplier by same authority | `procedure_type`, `contracting_entity_id`, winner NIF, `publication_date` | OECD: repeat awards and concentration over 3 years |
| A2 | Contract published after execution starts | `publication_date`, `celebration_date`, `execution_start_date` | OECD: contract data earlier than adjudication date |
| A3 | Execution begins before publication in BASE | `publication_date` vs actual start | OECD: contracts implemented before publication |
| A4 | Amendment inflation — large or frequent modifications | `base_price`, amendment value, amendment count | BASE publishes modifications above thresholds |
| A5 | Contract value just below procedural thresholds | `base_price`, `procedure_type` | Threshold-splitting / fragmentation |
| A6 | Single bidder / low-competition procedure | bidder count, `procedure_type` | BASE publishes procedure type and bidder details |
| A7 | Buyer uses direct award far above peer median for same CPV | `procedure_type`, `cpv_code`, `contracting_entity_id` | Peer comparison by CPV and region |
| A8 | Long execution duration (> 3 years) | contract duration | OECD: execution length over 3 years as risk feature |
| A9 | Estimated value vs final price anomaly | `base_price`, `total_effective_price` | OECD: ratios between estimated, base, and contract price |

### Track B — Pattern-based anomaly flags (statistical / model)

| # | Indicator | Approach |
|---|---|---|
| B1 | Bid rotation — suppliers who rarely compete except with one authority | Cluster analysis of winner NIF × authority pairs |
| B2 | Supplier concentration — share of buyer's spend to one supplier | Herfindahl-style concentration index by authority + CPV |
| B3 | Unusual pricing relative to CPV and region peers | Z-score or percentile within CPV × region × year |
| B4 | Sudden procedural shifts near budget deadlines | Time series of procedure type distribution per authority |

### Track C — Integrity and compliance risk

| # | Indicator | Data fields | Notes |
|---|---|---|---|
| C1 | Missing supplier NIF | `tax_identifier` null or invalid | OECD: VAT number completeness is itself a risk signal |
| C2 | Impossible date sequences | date ordering checks | Catches data manipulation or late entry |
| C3 | Missing mandatory fields by procedure type | CPV, location, base price | Absence is a risk signal, not just a data defect |
| C4 | Supplier overlap with AdC sanction cases | winner NIF × AdC case database | OECD: AdC sanctions enriched with NIF for cross-referencing |
| C5 | Entity name variations masking same entity | fuzzy match + NIF | Entity resolution is mandatory — names vary widely |
| C6 | Contract not submitted to TdC when required | TdC data (constrained) | Some indicators require TdC internal data |

### Data quality as a flag

Missing or inconsistent data is not just a technical defect — it can indicate evasion. Flag:
- Missing supplier NIF
- Missing CPV code
- Contract amendments with missing legal basis
- Repeated manual text variations for the same entity name
- Date fields outside plausible ranges

---

## Scoring Architecture

Each flagged case should carry:
- **Risk score** (weighted sum of active flags)
- **Evidence fields** (which fields triggered the flag)
- **Data completeness score** (fraction of expected fields present)
- **Confidence level** (low / medium / high — degrades when key fields are missing)

This prevents weak data from producing overconfident conclusions.

---

## Implementation Phases

**Phase 1 — Procurement spine + rule-based dashboard**
Build a clean BASE ingestion pipeline normalising core fields (contract ID, authority, supplier NIF, procedure type, CPV, prices, dates, amendment counts). Implement Track A red flags. Display on dashboard with severity filter.

**Phase 2 — External enrichment + competition indicators**
Add TED cross-checking and AdC sanction matching. Compute Track B concentration and competition pattern indicators.

**Phase 3 — Anomaly detection + case triage**
Statistical pricing and procedure anomalies. Build a case triage workflow with confidence scoring and evidence drill-down.

**Phase 4 — Ownership and conflict checks (constrained)**
Integrate RCBE where legally accessible. Treat as a constrained layer — CJEU ruling limits open access to beneficial ownership data.

---

## Escalation Routes (Portugal)

| Issue type | Route |
|---|---|
| Financial irregularity, unlawful spending, contract legality | Tribunal de Contas complaints channel (anonymous submissions accepted) |
| Cartel / bid rigging / anti-competitive conduct | Autoridade da Concorrência — report anti-competitive practices; leniency framework available |
| General corruption / whistleblowing | MENAC reporting channel; TdC whistleblower protections |

---

## Technical Standards

- **NIF/NIPC**: Always stored as a string to preserve leading zeros.
- **Currency**: `decimal` with precision 15, scale 2.
- **country_code**: ISO 3166-1 alpha-2 (PT, ES, FR…). Always 2 letters.
- **external_id**: ID from the original data source, unique within `[external_id, country_code]`.
- **adapter_class**: Must be within the `PublicContracts::` namespace and implement `#fetch_contracts`.
- **Testing**: Minitest. All HTTP stubbed — no live calls in the test suite. 100% SimpleCov line coverage.
- **UI**: Rails 8 + Hotwire + Tailwind CSS. Cyberpunk-noir aesthetic (`#0d0f14` background, `#c8a84e` gold, `#ff4444` red alerts).

## File Structure

```
app/
  models/                          Contract, Entity, ContractWinner, DataSource
  services/public_contracts/
    base_client.rb                 Generic HTTP client
    import_service.rb              Ingests contracts from a DataSource record
    pt/
      portal_base_client.rb        Portal BASE API
      dados_gov_client.rb          dados.gov.pt API
      registo_comercial.rb         publicacoes.mj.pt scraper
    eu/
      ted_client.rb                TED API v3
  controllers/
    dashboard_controller.rb        Main insight dashboard
docs/plans/                        Design docs and implementation plans
transparencia/                     Legacy Python scripts for data extraction
```

## Key Data Quality Notes

- BASE data quality is the responsibility of contracting entities — treat inconsistencies as risk signals.
- Entity resolution is mandatory: supplier names vary; always match on NIF where available, then fuzzy name + CPV.
- Some OECD indicators could not be developed due to data availability — document which flags are constrained.
- Beneficial ownership linkage is constrained by RCBE access rules and the CJEU ruling — do not assume it can be automated.
