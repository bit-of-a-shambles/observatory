# Multi-Country Data Source Architecture

**Date:** 2026-02-25
**Status:** Approved

---

## Problem

The app is currently hard-wired for Portugal. All services live flat in `PublicContracts/`, domain models carry no country context, and `external_id` uniqueness is global — which breaks as soon as a Spanish or French contract with the same numeric ID appears.

---

## Decision Summary

- **DB-driven** data source registry: each configured source is a row in `data_sources`.
- **No `countries` table**: active countries are derived from `DataSource.distinct.pluck(:country_code)`.
- **TED**: one `DataSource` record per country (e.g. "TED — PT", "TED — ES"), not one shared EU record.
- **SQLite** stays; `config` stored as JSON text with `serialize`.
- **Country namespace** for service classes: `PublicContracts::PT::*`, `PublicContracts::EU::*`.

---

## Database Changes

### New table: `data_sources`

| Column | Type | Notes |
|---|---|---|
| `country_code` | string, NOT NULL | ISO 3166-1 alpha-2 (PT, ES, FR…) |
| `name` | string, NOT NULL | "Portal BASE", "TED — PT" |
| `source_type` | string, NOT NULL | enum: `api` / `scraper` / `csv` |
| `adapter_class` | string, NOT NULL | Fully-qualified Ruby class name |
| `config` | text | JSON — API keys, base URLs, per-source options |
| `status` | string, default `inactive` | enum: `active` / `inactive` / `error` |
| `last_synced_at` | datetime | |
| `record_count` | integer, default 0 | Updated after each sync |
| `timestamps` | | |

### Modified: `entities`

- Add `country_code` string (NOT NULL once migrated; nullable for now with a sensible default `"PT"` on existing rows).
- Change DB index on `tax_identifier` from unique to a composite unique on `[tax_identifier, country_code]`.
- Update model validation accordingly.

### Modified: `contracts`

- Add `country_code` string.
- Add `data_source_id` integer (FK → `data_sources`, nullable — not all contracts will have a tracked source yet).

---

## Service Layer

### Directory structure

```
app/services/public_contracts/
  base_client.rb              ← generic HTTP (get/post), keep as-is
  import_service.rb           ← updated: accepts a DataSource record
  pt/
    portal_base_client.rb     ← was portal_base_client.rb
    dados_gov_client.rb       ← was dados_gov_client.rb
    registo_comercial.rb      ← was registo_comercial.rb
  eu/
    ted_client.rb             ← was ted_client.rb
```

### Adapter interface (duck-typed)

Every country adapter must implement:

```ruby
def fetch_contracts(page: 1, limit: 50) # → Array<Hash>
def country_code                         # → "PT", "ES", ...
def source_name                          # → "Portal BASE"
```

The hash returned by `fetch_contracts` must contain at minimum:
`external_id`, `object`, `country_code`, and optionally all other `Contract` fields.

### ImportService

```ruby
class ImportService
  def initialize(data_source_record)
    @ds      = data_source_record
    @adapter = @ds.adapter_class.constantize.new(@ds.config_hash)
  end

  def call
    contracts = @adapter.fetch_contracts
    contracts.each { |attrs| import_contract(attrs) }
    @ds.update!(status: :active, last_synced_at: Time.current, record_count: contracts.size)
  rescue => e
    @ds.update!(status: :error)
    raise
  end

  private

  def import_contract(attrs)
    # find_or_create entities (scoped to country_code)
    # find_or_create contract (external_id + country_code)
    # upsert contract_winners
  end
end
```

---

## Models

### DataSource

```ruby
class DataSource < ApplicationRecord
  serialize :config, coder: JSON

  enum :status, { inactive: "inactive", active: "active", error: "error" }

  has_many :contracts

  validates :country_code, :name, :adapter_class, :source_type, presence: true
  validates :source_type, inclusion: { in: %w[api scraper csv] }

  def config_hash
    config.is_a?(Hash) ? config : {}
  end

  def adapter
    adapter_class.constantize.new(config_hash)
  end
end
```

### Entity (updated)

- Add `country_code` attribute.
- Uniqueness on `[tax_identifier, country_code]`.

### Contract (updated)

- Add `country_code`, `data_source_id`.
- `belongs_to :data_source, optional: true`.

---

## Test Strategy (target: 100% coverage)

All HTTP is **stubbed** — no live calls in the test suite. Integration tests (TED, RegistoComercial) are kept as opt-in scripts, not part of `bin/rails test`.

| Test file | Covers |
|---|---|
| `test/models/data_source_test.rb` | validations, enum, `config_hash`, `adapter` instantiation |
| `test/models/entity_test.rb` | validations, scoped uniqueness, associations |
| `test/models/contract_test.rb` | validations, `data_source` association |
| `test/models/contract_winner_test.rb` | associations, `price_share` |
| `test/services/base_client_test.rb` | `get`: success, HTTP error, exception |
| `test/services/pt/portal_base_client_test.rb` | `fetch_contracts`, `find_contract`: success + error |
| `test/services/pt/dados_gov_client_test.rb` | `search_datasets`, `fetch_resource`: success + error |
| `test/services/pt/registo_comercial_test.rb` | NIPC/name validation, `extrair_socios`, `extrair_gerentes`, HTML parsing via fixture strings |
| `test/services/eu/ted_client_test.rb` | `search`, `portuguese_contracts`, `notices_for_country`: success + error + exception |
| `test/services/import_service_test.rb` | full import flow (mocked adapter), error → status update, `find_or_create` entity/contract logic |
| `test/controllers/dashboard_controller_test.rb` | GET index → 200 |

### HTTP stub approach

Use a lightweight module included in service tests:

```ruby
module StubHttp
  def stub_get(url, body:, code: "200")
    # swap Net::HTTP.get_response for a fake response
  end
  def stub_post(url, body:, code: "200")
    # swap Net::HTTP#request for a fake response
  end
end
```

No extra gems needed.

---

## What Does Not Change

- Dashboard controller and views — no country filter needed yet.
- Cyberpunk-noir design system.
- `RegistoComercial` internal logic — just moves to `pt/` namespace.
- SQLite, Minitest, SimpleCov setup.
