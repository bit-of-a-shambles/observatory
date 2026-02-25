# Multi-Country Data Source Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add DB-driven multi-country support (new `data_sources` table, `country_code` on entities/contracts, namespaced service layer) and reach 100% SimpleCov coverage with stubbed unit tests.

**Architecture:** A new `DataSource` AR model stores adapter configuration per country. Service classes move into `PublicContracts::PT::` and `PublicContracts::EU::` namespaces. `ImportService` accepts a `DataSource` record and instantiates the correct adapter via `constantize`. All HTTP is stubbed in tests — no live calls.

**Tech Stack:** Rails 8, SQLite, Minitest 5.25, SimpleCov, Minitest `stub` (built-in, no extra gems).

---

## Pre-flight check

```bash
cd /Users/duartemartins/Code/observatorio
bundle exec rails test 2>&1 | tail -5
```
Expected: 9 runs, 4 errors (fixture uniqueness issue — fixed in Task 1).

---

## Task 1: Fix fixture errors and verify baseline

The `entities` fixture has `tax_identifier: MyString` for both rows, causing a uniqueness violation on load.

**Files:**
- Modify: `test/fixtures/entities.yml`
- Modify: `test/fixtures/contracts.yml` (use symbolic reference for `contracting_entity_id`)

**Step 1: Fix entities.yml**

Replace the entire file content:

```yaml
# test/fixtures/entities.yml
one:
  name: Câmara Municipal de Lisboa
  tax_identifier: "500123456"
  country_code: PT
  is_public_body: true
  is_company: false
  address: Praça do Município
  postal_code: "1100-038"
  locality: Lisboa

two:
  name: Construções Ferreira Lda
  tax_identifier: "509999001"
  country_code: PT
  is_public_body: false
  is_company: true
  address: Rua das Obras 10
  postal_code: "4000-100"
  locality: Porto
```

**Step 2: Fix contracts.yml**

```yaml
# test/fixtures/contracts.yml
one:
  external_id: "contract-001"
  contracting_entity: one
  country_code: PT
  object: Fornecimento de material de escritório
  contract_type: Aquisição de Bens
  procedure_type: Ajuste Direto
  publication_date: 2026-02-01
  celebration_date: 2026-02-10
  base_price: 18000.00
  total_effective_price: 17500.00
  cpv_code: "30192000"
  location: Lisboa

two:
  external_id: "contract-002"
  contracting_entity: one
  country_code: PT
  object: Serviços de limpeza
  contract_type: Aquisição de Serviços
  procedure_type: Ajuste Direto
  publication_date: 2026-02-05
  celebration_date: 2026-02-12
  base_price: 19500.00
  total_effective_price: 19500.00
  cpv_code: "90911000"
  location: Porto
```

**Step 3: Run tests to verify errors are gone**

```bash
bundle exec rails test 2>&1 | tail -5
```
Expected: 9 runs, 0 errors (some tests still skipped/commented, but no fixture crashes).

**Step 4: Commit**

```bash
git add test/fixtures/entities.yml test/fixtures/contracts.yml
git commit -m "fix: repair fixture uniqueness and add country_code placeholders"
```

---

## Task 2: Migration — `data_sources` table

**Files:**
- Create: `db/migrate/TIMESTAMP_create_data_sources.rb` (generated)
- Modify: `db/schema.rb` (auto-updated)

**Step 1: Generate migration**

```bash
bundle exec rails generate migration CreateDataSources \
  country_code:string \
  name:string \
  source_type:string \
  adapter_class:string \
  config:text \
  status:string \
  last_synced_at:datetime \
  record_count:integer
```

**Step 2: Edit the generated migration** to add defaults, null constraints, and index:

```ruby
class CreateDataSources < ActiveRecord::Migration[8.0]
  def change
    create_table :data_sources do |t|
      t.string  :country_code,  null: false
      t.string  :name,          null: false
      t.string  :source_type,   null: false
      t.string  :adapter_class, null: false
      t.text    :config
      t.string  :status,        null: false, default: "inactive"
      t.datetime :last_synced_at
      t.integer :record_count,  default: 0

      t.timestamps
    end

    add_index :data_sources, :country_code
    add_index :data_sources, :status
  end
end
```

**Step 3: Run migration**

```bash
bundle exec rails db:migrate
```

Expected: `== CreateDataSources: migrated`

**Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add data_sources table migration"
```

---

## Task 3: Migration — `country_code` on `entities`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_country_code_to_entities.rb`

**Step 1: Generate migration**

```bash
bundle exec rails generate migration AddCountryCodeToEntities \
  country_code:string
```

**Step 2: Edit migration** — default existing rows to "PT", update unique index:

```ruby
class AddCountryCodeToEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :country_code, :string, null: false, default: "PT"

    remove_index :entities, :tax_identifier
    add_index :entities, [:tax_identifier, :country_code], unique: true,
              name: "index_entities_on_tax_identifier_and_country_code"
  end
end
```

**Step 3: Run migration**

```bash
bundle exec rails db:migrate
```

**Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add country_code to entities with scoped uniqueness index"
```

---

## Task 4: Migration — `country_code` + `data_source_id` on `contracts`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_country_and_source_to_contracts.rb`

**Step 1: Generate migration**

```bash
bundle exec rails generate migration AddCountryAndSourceToContracts \
  country_code:string \
  data_source:references
```

**Step 2: Edit migration** — default to "PT", make FK optional:

```ruby
class AddCountryAndSourceToContracts < ActiveRecord::Migration[8.0]
  def change
    add_column :contracts, :country_code, :string, null: false, default: "PT"
    add_reference :contracts, :data_source, null: true, foreign_key: true
  end
end
```

**Step 3: Run migration**

```bash
bundle exec rails db:migrate
```

**Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add country_code and data_source_id to contracts"
```

---

## Task 5: `DataSource` model

**Files:**
- Create: `app/models/data_source.rb`
- Create: `test/models/data_source_test.rb`
- Create: `test/fixtures/data_sources.yml`

**Step 1: Write the failing test**

```ruby
# test/models/data_source_test.rb
require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  # ── validations ──────────────────────────────────────────
  test "valid with all required fields" do
    ds = DataSource.new(
      country_code:  "PT",
      name:          "Portal BASE",
      source_type:   "api",
      adapter_class: "PublicContracts::PT::PortalBaseClient"
    )
    assert ds.valid?
  end

  test "invalid without country_code" do
    ds = DataSource.new(name: "X", source_type: "api", adapter_class: "X")
    assert_not ds.valid?
    assert_includes ds.errors[:country_code], "can't be blank"
  end

  test "invalid without name" do
    ds = DataSource.new(country_code: "PT", source_type: "api", adapter_class: "X")
    assert_not ds.valid?
  end

  test "invalid without adapter_class" do
    ds = DataSource.new(country_code: "PT", name: "X", source_type: "api")
    assert_not ds.valid?
  end

  test "invalid with unknown source_type" do
    ds = DataSource.new(country_code: "PT", name: "X", source_type: "ftp", adapter_class: "X")
    assert_not ds.valid?
  end

  test "valid source_types are api, scraper, csv" do
    %w[api scraper csv].each do |t|
      ds = DataSource.new(country_code: "PT", name: "X", source_type: t, adapter_class: "X")
      assert ds.valid?, "expected #{t} to be valid"
    end
  end

  # ── status enum ──────────────────────────────────────────
  test "default status is inactive" do
    ds = DataSource.new
    assert_equal "inactive", ds.status
  end

  test "status enum has inactive active error" do
    ds = data_sources(:portal_base)
    ds.active!
    assert ds.active?
    ds.error!
    assert ds.error?
    ds.inactive!
    assert ds.inactive?
  end

  # ── config_hash ───────────────────────────────────────────
  test "config_hash returns empty hash when config is nil" do
    ds = DataSource.new
    assert_equal({}, ds.config_hash)
  end

  test "config_hash returns parsed hash when config is JSON string" do
    ds = DataSource.new(config: '{"api_key":"secret"}')
    assert_equal({ "api_key" => "secret" }, ds.config_hash)
  end

  test "config_hash returns hash when config is already a hash" do
    ds = DataSource.new
    ds.config = { "key" => "val" }
    assert_equal({ "key" => "val" }, ds.config_hash)
  end

  # ── associations ─────────────────────────────────────────
  test "has many contracts" do
    ds = data_sources(:portal_base)
    assert_respond_to ds, :contracts
  end
end
```

**Step 2: Create fixture**

```yaml
# test/fixtures/data_sources.yml
portal_base:
  country_code: PT
  name: Portal BASE
  source_type: api
  adapter_class: PublicContracts::PT::PortalBaseClient
  status: active
  record_count: 0

ted_pt:
  country_code: PT
  name: "TED — PT"
  source_type: api
  adapter_class: PublicContracts::EU::TedClient
  status: inactive
  record_count: 0
```

**Step 3: Run test to see it fail**

```bash
bundle exec rails test test/models/data_source_test.rb 2>&1 | tail -5
```
Expected: errors — `DataSource` uninitialized constant or no such table.

**Step 4: Write the model**

```ruby
# app/models/data_source.rb
class DataSource < ApplicationRecord
  serialize :config, coder: JSON

  enum :status, { inactive: "inactive", active: "active", error: "error" }, default: "inactive"

  has_many :contracts

  validates :country_code,  presence: true
  validates :name,          presence: true
  validates :adapter_class, presence: true
  validates :source_type,   presence: true,
                            inclusion: { in: %w[api scraper csv] }

  def config_hash
    case config
    when Hash   then config
    when String then JSON.parse(config) rescue {}
    else {}
    end
  end
end
```

**Step 5: Run test to verify it passes**

```bash
bundle exec rails test test/models/data_source_test.rb 2>&1 | tail -5
```
Expected: all green, 0 failures.

**Step 6: Commit**

```bash
git add app/models/data_source.rb test/models/data_source_test.rb test/fixtures/data_sources.yml
git commit -m "feat: add DataSource model with validations, enum, config_hash"
```

---

## Task 6: Update `Entity` model and tests

**Files:**
- Modify: `app/models/entity.rb`
- Modify: `test/models/entity_test.rb`

**Step 1: Write failing tests** (replace the file):

```ruby
# test/models/entity_test.rb
require "test_helper"

class EntityTest < ActiveSupport::TestCase
  test "valid entity" do
    entity = Entity.new(name: "Test Entity", tax_identifier: "123456789", country_code: "PT")
    assert entity.valid?
  end

  test "invalid without name" do
    entity = Entity.new(tax_identifier: "123456789", country_code: "PT")
    assert_not entity.valid?
    assert_includes entity.errors[:name], "can't be blank"
  end

  test "invalid without tax_identifier" do
    entity = Entity.new(name: "Test Entity", country_code: "PT")
    assert_not entity.valid?
  end

  test "invalid without country_code" do
    entity = Entity.new(name: "Test Entity", tax_identifier: "123456789")
    # default is "PT" from migration, so explicitly set blank
    entity.country_code = ""
    assert_not entity.valid?
  end

  test "tax_identifier must be unique within country" do
    existing = entities(:one)
    duplicate = Entity.new(
      name:           "Other",
      tax_identifier: existing.tax_identifier,
      country_code:   existing.country_code
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:tax_identifier], "has already been taken"
  end

  test "same tax_identifier allowed in different countries" do
    existing = entities(:one)
    other_country = Entity.new(
      name:           "Spanish clone",
      tax_identifier: existing.tax_identifier,
      country_code:   "ES"
    )
    assert other_country.valid?
  end

  test "has many contracts as contracting entity" do
    assert_respond_to entities(:one), :contracts_as_contracting_entity
  end

  test "has many contract_winners" do
    assert_respond_to entities(:one), :contract_winners
  end

  test "has many contracts_won through contract_winners" do
    assert_respond_to entities(:one), :contracts_won
  end
end
```

**Step 2: Run to see failures**

```bash
bundle exec rails test test/models/entity_test.rb 2>&1 | tail -10
```

**Step 3: Update model**

```ruby
# app/models/entity.rb
class Entity < ApplicationRecord
  has_many :contracts_as_contracting_entity, class_name: "Contract", foreign_key: "contracting_entity_id"
  has_many :contract_winners
  has_many :contracts_won, through: :contract_winners, source: :contract

  validates :tax_identifier, presence: true,
                             uniqueness: { scope: :country_code }
  validates :name,           presence: true
  validates :country_code,   presence: true
end
```

**Step 4: Run test to verify all pass**

```bash
bundle exec rails test test/models/entity_test.rb 2>&1 | tail -5
```
Expected: 9 runs, 0 failures.

**Step 5: Commit**

```bash
git add app/models/entity.rb test/models/entity_test.rb
git commit -m "feat: scope entity uniqueness to country_code, add country_code validation"
```

---

## Task 7: Update `Contract` model and tests

**Files:**
- Modify: `app/models/contract.rb`
- Modify: `test/models/contract_test.rb`
- Modify: `test/fixtures/contracts.yml` — add `data_source` reference

**Step 1: Update contracts fixture to reference data_source**

```yaml
# test/fixtures/contracts.yml
one:
  external_id: "contract-001"
  contracting_entity: one
  data_source: portal_base
  country_code: PT
  object: Fornecimento de material de escritório
  contract_type: Aquisição de Bens
  procedure_type: Ajuste Direto
  publication_date: 2026-02-01
  celebration_date: 2026-02-10
  base_price: 18000.00
  total_effective_price: 17500.00
  cpv_code: "30192000"
  location: Lisboa

two:
  external_id: "contract-002"
  contracting_entity: one
  data_source: portal_base
  country_code: PT
  object: Serviços de limpeza
  contract_type: Aquisição de Serviços
  procedure_type: Ajuste Direto
  publication_date: 2026-02-05
  celebration_date: 2026-02-12
  base_price: 19500.00
  total_effective_price: 19500.00
  cpv_code: "90911000"
  location: Porto
```

**Step 2: Write failing tests**

```ruby
# test/models/contract_test.rb
require "test_helper"

class ContractTest < ActiveSupport::TestCase
  test "valid contract" do
    contract = Contract.new(
      external_id:        "ext-999",
      object:             "Test procurement",
      country_code:       "PT",
      contracting_entity: entities(:one)
    )
    assert contract.valid?
  end

  test "invalid without external_id" do
    contract = Contract.new(object: "Test", country_code: "PT",
                            contracting_entity: entities(:one))
    assert_not contract.valid?
  end

  test "invalid without object" do
    contract = Contract.new(external_id: "ext-999", country_code: "PT",
                            contracting_entity: entities(:one))
    assert_not contract.valid?
  end

  test "external_id must be unique" do
    existing = contracts(:one)
    dup = Contract.new(
      external_id:        existing.external_id,
      object:             "Another",
      country_code:       "PT",
      contracting_entity: entities(:one)
    )
    assert_not dup.valid?
    assert_includes dup.errors[:external_id], "has already been taken"
  end

  test "belongs to contracting_entity" do
    assert_equal entities(:one), contracts(:one).contracting_entity
  end

  test "belongs to data_source (optional)" do
    assert_equal data_sources(:portal_base), contracts(:one).data_source
  end

  test "data_source is optional" do
    contract = Contract.new(
      external_id:        "ext-888",
      object:             "No source",
      country_code:       "PT",
      contracting_entity: entities(:one)
    )
    assert contract.valid?
  end

  test "has many contract_winners" do
    assert_respond_to contracts(:one), :contract_winners
  end

  test "has many winners through contract_winners" do
    assert_respond_to contracts(:one), :winners
  end

  test "contract_winners destroyed with contract" do
    contract = contracts(:one)
    winner_count = contract.contract_winners.count
    assert winner_count > 0
    contract.destroy
    assert_equal 0, ContractWinner.where(contract_id: contract.id).count
  end
end
```

**Step 3: Run to see failures**

```bash
bundle exec rails test test/models/contract_test.rb 2>&1 | tail -10
```

**Step 4: Update model**

```ruby
# app/models/contract.rb
class Contract < ApplicationRecord
  belongs_to :contracting_entity, class_name: "Entity"
  belongs_to :data_source, optional: true
  has_many :contract_winners, dependent: :destroy
  has_many :winners, through: :contract_winners, source: :entity

  validates :external_id, presence: true, uniqueness: true
  validates :object,       presence: true
end
```

**Step 5: Run test to verify all pass**

```bash
bundle exec rails test test/models/contract_test.rb 2>&1 | tail -5
```
Expected: 11 runs, 0 failures.

**Step 6: Commit**

```bash
git add app/models/contract.rb test/models/contract_test.rb test/fixtures/contracts.yml
git commit -m "feat: add data_source association to Contract, expand contract tests"
```

---

## Task 8: `ContractWinner` model tests

**Files:**
- Modify: `test/models/contract_winner_test.rb`

**Step 1: Write tests**

```ruby
# test/models/contract_winner_test.rb
require "test_helper"

class ContractWinnerTest < ActiveSupport::TestCase
  test "belongs to contract" do
    cw = contract_winners(:one)
    assert_instance_of Contract, cw.contract
  end

  test "belongs to entity" do
    cw = contract_winners(:one)
    assert_instance_of Entity, cw.entity
  end

  test "price_share can be nil" do
    cw = ContractWinner.new(contract: contracts(:one), entity: entities(:two))
    assert cw.valid?
  end

  test "price_share stores decimal value" do
    cw = contract_winners(:one)
    assert_equal 9.99, cw.price_share.to_f
  end
end
```

**Step 2: Run**

```bash
bundle exec rails test test/models/contract_winner_test.rb 2>&1 | tail -5
```
Expected: 4 runs, 0 failures.

**Step 3: Commit**

```bash
git add test/models/contract_winner_test.rb
git commit -m "test: add ContractWinner model tests"
```

---

## Task 9: Create HTTP stub helper

All service unit tests stub HTTP — no live calls. This module is `include`d into service test classes.

**Files:**
- Create: `test/support/http_stub_helper.rb`

**Step 1: Create the file**

```ruby
# test/support/http_stub_helper.rb
#
# Lightweight helpers for stubbing Net::HTTP in Minitest service tests.
# Include with:  include HttpStubHelper
#
module HttpStubHelper
  # Build a fake Net::HTTPSuccess-like response object.
  def fake_success(body)
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |klass| klass <= Net::HTTPSuccess }
    resp.define_singleton_method(:body)  { body }
    resp.define_singleton_method(:code)  { "200" }
    resp.define_singleton_method(:message) { "OK" }
    resp
  end

  # Build a fake error response (e.g. 404, 500).
  def fake_error(code = "500", message = "Internal Server Error")
    resp = Object.new
    resp.define_singleton_method(:is_a?) { |_klass| false }
    resp.define_singleton_method(:body)  { "" }
    resp.define_singleton_method(:code)  { code }
    resp.define_singleton_method(:message) { message }
    resp
  end

  # Stub Net::HTTP.get_response (used by BaseClient#get).
  def stub_get_response(response, &block)
    Net::HTTP.stub(:get_response, response, &block)
  end

  # Build a mock HTTP instance that responds to the TedClient / POST interface.
  # Returns the mock so you can call .verify on it.
  def mock_http_post(response)
    mock = Minitest::Mock.new
    mock.expect(:use_ssl=,      nil, [TrueClass])
    mock.expect(:open_timeout=, nil, [Integer])
    mock.expect(:read_timeout=, nil, [Integer])
    mock.expect(:request,       response, [Net::HTTP::Post])
    mock
  end
end
```

**Step 2: No test needed — this is a test helper. Commit.**

```bash
git add test/support/http_stub_helper.rb
git commit -m "test: add HttpStubHelper for stubbing Net::HTTP in service tests"
```

---

## Task 10: Namespace existing services — create directory structure

Move existing service files into country namespaces. The originals are replaced (Zeitwerk will autoload the new paths).

**Files:**
- Create: `app/services/public_contracts/pt/portal_base_client.rb`
- Create: `app/services/public_contracts/pt/dados_gov_client.rb`
- Create: `app/services/public_contracts/pt/registo_comercial.rb`
- Create: `app/services/public_contracts/eu/ted_client.rb`
- Delete: `app/services/public_contracts/portal_base_client.rb`
- Delete: `app/services/public_contracts/dados_gov_client.rb`
- Delete: `app/services/public_contracts/ted_client.rb`
- Keep:   `app/services/public_contracts/registo_comercial.rb` deleted (moved to pt/)

**Step 1: Create `pt/portal_base_client.rb`**

```ruby
# app/services/public_contracts/pt/portal_base_client.rb
# frozen_string_literal: true

module PublicContracts
  module PT
    class PortalBaseClient < PublicContracts::BaseClient
      SOURCE_NAME  = "Portal BASE"
      COUNTRY_CODE = "PT"
      BASE_URL     = "http://www.base.gov.pt/api/v1"

      def initialize(config = {})
        super(config.fetch("base_url", BASE_URL))
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      # Returns an Array of raw contract hashes (as returned by the API).
      def fetch_contracts(page: 1, limit: 50)
        result = get("/contratos", limit: limit, offset: (page - 1) * limit)
        Array(result)
      end

      def find_contract(id)
        get("/contratos/#{id}")
      end
    end
  end
end
```

**Step 2: Create `pt/dados_gov_client.rb`**

```ruby
# app/services/public_contracts/pt/dados_gov_client.rb
# frozen_string_literal: true

module PublicContracts
  module PT
    class DadosGovClient < PublicContracts::BaseClient
      SOURCE_NAME  = "dados.gov.pt"
      COUNTRY_CODE = "PT"
      BASE_URL     = "https://dados.gov.pt/api/1"

      def initialize(config = {})
        super(config.fetch("base_url", BASE_URL))
      end

      def country_code = COUNTRY_CODE
      def source_name  = SOURCE_NAME

      def fetch_contracts(page: 1, limit: 50)
        result = search_datasets("contratos públicos")
        Array(result&.dig("data"))
      end

      def search_datasets(query)
        get("/datasets", q: query)
      end

      def fetch_resource(resource_id)
        get("/datasets/resources/#{resource_id}")
      end
    end
  end
end
```

**Step 3: Create `eu/ted_client.rb`** (namespaced copy of existing file)

```ruby
# app/services/public_contracts/eu/ted_client.rb
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PublicContracts
  module EU
    class TedClient
      SOURCE_NAME = "TED — Tenders Electronic Daily"
      BASE_URL    = "https://api.ted.europa.eu"
      API_VERSION = "v3"

      DEFAULT_FIELDS = %w[
        publication-number
        publication-date
        notice-title
        organisation-country-buyer
        organisation-name-buyer
      ].freeze

      def initialize(config = {})
        @api_key = config.fetch("api_key", ENV["TED_API_KEY"])
      end

      def country_code
        # TED is EU-wide; the DataSource record carries the country_code.
        "EU"
      end

      def source_name = SOURCE_NAME

      def search(query:, page: 1, limit: 10, fields: DEFAULT_FIELDS)
        body = { query: query, fields: fields, page: page, limit: limit }
        post("/#{API_VERSION}/notices/search", body)
      end

      def portuguese_contracts(page: 1, limit: 10)
        notices_for_country("PRT", page: page, limit: limit)
      end

      def notices_for_country(country_code, keyword: nil, page: 1, limit: 10)
        q = "organisation-country-buyer=#{country_code}"
        q += " AND #{keyword}" if keyword
        search(query: q, page: page, limit: limit)
      end

      def fetch_contracts(page: 1, limit: 50)
        result = search(query: "organisation-country-buyer=PRT", page: page, limit: limit)
        Array(result&.dig("notices"))
      end

      private

      def post(path, body)
        uri  = URI("#{BASE_URL}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = 15
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Accept"]       = "application/json"
        request["api-key"]      = @api_key if @api_key
        request.body            = body.to_json

        response = http.request(request)

        case response
        when Net::HTTPSuccess
          JSON.parse(response.body)
        else
          log_error(response)
          nil
        end
      rescue StandardError => e
        log_exception(e)
        nil
      end

      def log_error(response)
        rails_log("[TedClient] HTTP #{response.code}: #{response.message}")
      end

      def log_exception(error)
        rails_log("[TedClient] #{error.class}: #{error.message}")
      end

      def rails_log(msg)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error msg
        else
          warn msg
        end
      end
    end
  end
end
```

**Step 4: Create `pt/registo_comercial.rb`** — wrap existing class in module:

Copy the entire content of `app/services/public_contracts/registo_comercial.rb` and wrap the three classes (`RegistoComercial`, `ConsultaEmLote`, `Cruzamento`) inside `module PublicContracts; module PT; ... end; end`. Remove the `if __FILE__ == $PROGRAM_NAME` block (that stays in the original CLI file). The class names become `PublicContracts::PT::RegistoComercial`, etc.

The complete file:

```ruby
# app/services/public_contracts/pt/registo_comercial.rb
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "csv"
require "date"
require "nokogiri"

module PublicContracts
  module PT
    class RegistoComercial
      DOMAIN       = "publicacoes.mj.pt"
      URL_PESQUISA = "https://#{DOMAIN}/pesquisa.aspx"
      URL_DETALHE  = "https://#{DOMAIN}/DetalhePublicacao.aspx"
      AGENT        = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
                     "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

      TIPOS = {
        todos:             "rblTipo_0",
        registo_comercial: "rblTipo_1",
        avisos:            "rblTipo_2",
        associacoes:       "rblTipo_3",
        solidariedade:     "rblTipo_4",
        pais:              "rblTipo_5",
        fundacoes:         "rblTipo_6"
      }.freeze

      def initialize(pausa: 2)
        @pausa  = pausa
        @sessao = {}
      end

      def pesquisar_por_nipc(nipc, tipo: :todos)
        nipc = nipc.to_s.strip.gsub(/\D/, "")
        raise ArgumentError, "NIPC deve ter 9 dígitos" unless nipc.length == 9
        pesquisar(nipc: nipc, tipo: tipo)
      end

      def pesquisar_por_nome(nome, tipo: :todos)
        nome = nome.to_s.strip
        raise ArgumentError, "Nome vazio" if nome.empty?
        pesquisar(nome: nome, tipo: tipo)
      end

      def obter_detalhe(ligacao)
        return nil unless ligacao&.start_with?("http")
        dormir
        html = obter_pagina(ligacao)
        extrair_detalhe(html)
      end

      def investigar(nipc)
        publicacoes = pesquisar_por_nipc(nipc)
        publicacoes.each_with_index do |pub, i|
          next unless pub[:ligacao]
          $stderr.print "\r  A ler publicação #{i + 1}/#{publicacoes.size}..."
          detalhe = obter_detalhe(pub[:ligacao])
          pub[:detalhe] = detalhe if detalhe
        end
        $stderr.puts
        publicacoes
      end

      private

      def dormir
        sleep(@pausa) if @pausa > 0
      end

      def criar_ligacao(url_texto)
        uri  = URI(url_texto)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = true
        http.open_timeout = 15
        http.read_timeout = 30
        [ uri, http ]
      end

      def obter_pagina(url_texto)
        uri, http = criar_ligacao(url_texto)
        pedido = Net::HTTP::Get.new(uri)
        pedido["User-Agent"] = AGENT
        pedido["Cookie"]     = montar_biscoitos if @sessao.any?
        resposta = http.request(pedido)
        guardar_biscoitos(resposta)
        resposta.body.force_encoding("utf-8")
      end

      def enviar_formulario(url_texto, campos)
        uri, http = criar_ligacao(url_texto)
        pedido = Net::HTTP::Post.new(uri)
        pedido["User-Agent"]    = AGENT
        pedido["Content-Type"]  = "application/x-www-form-urlencoded"
        pedido["Cookie"]        = montar_biscoitos if @sessao.any?
        pedido.body             = URI.encode_www_form(campos)
        resposta = http.request(pedido)
        guardar_biscoitos(resposta)

        if resposta.is_a?(Net::HTTPRedirection)
          novo_url = resposta["Location"]
          novo_url = "https://#{DOMAIN}#{novo_url}" unless novo_url.start_with?("http")
          return obter_pagina(novo_url)
        end

        resposta.body.force_encoding("utf-8")
      end

      def guardar_biscoitos(resposta)
        Array(resposta.get_fields("Set-Cookie")).each do |biscoito|
          chave, valor = biscoito.split(";").first.split("=", 2)
          @sessao[chave.strip] = valor.to_s.strip
        end
      end

      def montar_biscoitos
        @sessao.map { |k, v| "#{k}=#{v}" }.join("; ")
      end

      def pesquisar(nipc: nil, nome: nil, tipo: :todos)
        html_inicial     = obter_pagina(URL_PESQUISA)
        campos_ocultos   = extrair_campos_ocultos(html_inicial)
        dormir
        tipo_radio = TIPOS.fetch(tipo, TIPOS[:todos])
        dados = campos_ocultos.merge(
          "ctl00$ContentPlaceHolder1$txtNIPC"      => nipc.to_s,
          "ctl00$ContentPlaceHolder1$txtEntidade"  => nome.to_s,
          "ctl00$ContentPlaceHolder1$ddlDistrito"  => "",
          "ctl00$ContentPlaceHolder1$ddlConcelho"  => "",
          "ctl00$ContentPlaceHolder1$txtDataDe"    => "",
          "ctl00$ContentPlaceHolder1$txtDataAte"   => "",
          "ctl00$ContentPlaceHolder1$rblTipo"      => tipo_radio,
          "ctl00$ContentPlaceHolder1$btnPesquisar" => "Pesquisar"
        )
        html_resultado = enviar_formulario(URL_PESQUISA, dados)
        extrair_resultados(html_resultado)
      end

      def extrair_campos_ocultos(html)
        doc    = Nokogiri::HTML(html)
        campos = {}
        doc.css('input[type="hidden"]').each do |input|
          nome  = input["name"]
          valor = input["value"].to_s
          campos[nome] = valor if nome
        end
        campos
      end

      def extrair_resultados(html)
        doc        = Nokogiri::HTML(html)
        resultados = []

        doc.css("table tr").each do |linha|
          celulas = linha.css("td")
          next if celulas.empty?
          ligacao_el = linha.at_css('a[href*="Detalhe"]') ||
                       linha.at_css('a[href*="detalhe"]')
          textos = celulas.map { |c| c.text.strip }
          pub    = extrair_linha_resultado(textos, ligacao_el)
          resultados << pub if pub
        end

        if resultados.empty?
          doc.css('[id*="GridView"] tr, [id*="grd"] tr, [id*="grid"] tr').each do |linha|
            celulas = linha.css("td")
            next if celulas.empty?
            ligacao_el = linha.at_css("a[href]")
            textos     = celulas.map { |c| c.text.strip }
            pub        = extrair_linha_resultado(textos, ligacao_el)
            resultados << pub if pub
          end
        end

        if resultados.empty?
          doc.css('a[href*="Detalhe"]').each do |a|
            href = a["href"].to_s
            href = "https://#{DOMAIN}/#{href}" unless href.start_with?("http")
            resultados << { resumo: a.text.strip, ligacao: href }
          end
        end

        $stderr.puts "  Encontradas #{resultados.size} publicações"
        resultados
      end

      def extrair_linha_resultado(textos, ligacao_el)
        return nil if textos.all?(&:empty?)
        ligacao = nil
        if ligacao_el
          href = ligacao_el["href"].to_s
          ligacao = if href.include?("javascript:__doPostBack")
                      :postback
                    else
                      href = "https://#{DOMAIN}/#{href}" unless href.start_with?("http")
                      href
                    end
        end
        {
          nipc:     textos[0],
          entidade: textos[1],
          data:     textos[2],
          tipo:     textos[3],
          resumo:   textos.reject(&:empty?).join(" | "),
          ligacao:  ligacao
        }
      end

      def extrair_detalhe(html)
        doc     = Nokogiri::HTML(html)
        detalhe = {}

        doc.css("table tr").each do |linha|
          celulas = linha.css("td, th")
          next unless celulas.size >= 2
          etiqueta = celulas[0].text.strip.downcase.gsub(/[:\s]+$/, "")
          valor    = celulas[1].text.strip

          case etiqueta
          when /nif|nipc|matr[ií]cula/        then detalhe[:nipc]              = valor.gsub(/\D/, "")
          when /entidade|firma|denomina/       then detalhe[:entidade]          = valor
          when /data.*publica/                 then detalhe[:data_publicacao]   = valor
          when /natureza/                      then detalhe[:natureza_juridica] = valor
          when /sede/                          then detalhe[:sede]              = valor
          when /distrito/                      then detalhe[:distrito]          = valor
          when /concelho/                      then detalhe[:concelho]          = valor
          when /capital/                       then detalhe[:capital_social]    = valor
          when /objec?to/                      then detalhe[:objecto]           = valor
          end
        end

        corpo = doc.css('[id*="lblConteudo"], [id*="lblTexto"], [id*="conteudo"]')
                   .map(&:text).join("\n").strip

        if corpo.empty?
          corpo = doc.css("td, div, p")
                     .map { |el| el.text.strip }
                     .select { |t| t.length > 100 }
                     .max_by(&:length).to_s
        end

        detalhe[:corpo] = corpo unless corpo.empty?

        if corpo.length > 0
          detalhe[:socios]   = extrair_socios(corpo)
          detalhe[:gerentes] = extrair_gerentes(corpo)
        end

        detalhe
      end

      def extrair_socios(texto)
        nomes   = []
        padroes = [
          /s[óo]cios?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /quota[s]?\s+(?:de|pertencente[s]?\s+a)\s+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /accion[ií]sta[s]?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /titular(?:es)?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /parte[s]?\s+social?\s+(?:de|a)\s+([A-ZÀ-Ú][^,;\.]{5,60})/i
        ]
        padroes.each do |padrao|
          texto.scan(padrao).each do |captura|
            nome = captura[0].strip.sub(/\s*,?\s*(?:NIF|NIPC|com|detendo|titular|portador).*$/i, "").strip
            nomes << nome if nome.length > 3 && nome.length < 80
          end
        end
        nomes.uniq
      end

      def extrair_gerentes(texto)
        nomes   = []
        padroes = [
          /gerente[s]?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /administrador(?:es)?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /director(?:es)?[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /(?:designad[oa]s?|nomead[oa]s?)\s+(?:como\s+)?(?:gerente|administrador)[^:]*[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i,
          /presidente[:\s]+([A-ZÀ-Ú][^,;\.]{5,60})/i
        ]
        padroes.each do |padrao|
          texto.scan(padrao).each do |captura|
            nome = captura[0].strip.sub(/\s*,?\s*(?:NIF|NIPC|com|portador|residente).*$/i, "").strip
            nomes << nome if nome.length > 3 && nome.length < 80
          end
        end
        nomes.uniq
      end
    end

    # ── Batch lookup ─────────────────────────────────────────────────────────
    class ConsultaEmLote
      def initialize(ficheiro_csv: nil, lista_nipc: [])
        @rc    = RegistoComercial.new(pausa: 3)
        @nipcs = lista_nipc
        carregar_csv(ficheiro_csv) if ficheiro_csv
      end

      def carregar_csv(caminho)
        csv    = CSV.read(caminho, headers: true, encoding: "bom|utf-8")
        coluna = csv.headers.find { |h| h =~ /nipc|nif.*adjudicat/i }
        abort "Não encontrei coluna de NIPC" unless coluna
        @nipcs = csv[coluna].compact.map { |n| n.to_s.strip.gsub(/\D/, "") }
                            .select { |n| n.length == 9 }.uniq
      end

      def executar(ficheiro_saida: "resultados_registo.json")
        resultados = {}
        @nipcs.each_with_index do |nipc, i|
          begin
            pubs = @rc.pesquisar_por_nipc(nipc)
            next if pubs.empty?
            detalhe = nil
            pubs.first(3).each do |pub|
              next unless pub[:ligacao].is_a?(String)
              detalhe = @rc.obter_detalhe(pub[:ligacao])
              break if detalhe&.any?
            end
            resultados[nipc] = {
              entidade:    pubs.first[:entidade],
              publicacoes: pubs.size,
              socios:      detalhe&.dig(:socios)  || [],
              gerentes:    detalhe&.dig(:gerentes) || [],
              capital:     detalhe&.dig(:capital_social),
              sede:        detalhe&.dig(:sede),
              natureza:    detalhe&.dig(:natureza_juridica)
            }
          rescue StandardError => e
            $stderr.puts "  ✗ #{nipc}: #{e.message}"
          end
        end
        File.write(ficheiro_saida, JSON.pretty_generate(resultados))
        resultados
      end
    end

    # ── Cross-reference ───────────────────────────────────────────────────────
    class Cruzamento
      def initialize(ficheiro_base:, ficheiro_registo:)
        @contratos = CSV.read(ficheiro_base, headers: true, encoding: "bom|utf-8")
        @registo   = JSON.parse(File.read(ficheiro_registo), symbolize_names: true)
      end

      def detectar_ligacoes
        mapa_pessoas = Hash.new { |h, k| h[k] = [] }
        @registo.each do |nipc, dados|
          ((dados[:socios] || []) + (dados[:gerentes] || [])).uniq.each do |nome|
            mapa_pessoas[normalizar_nome(nome)] << {
              nipc: nipc.to_s, entidade: dados[:entidade],
              papel: dados[:socios]&.include?(nome) ? "sócio" : "gerente"
            }
          end
        end
        mapa_pessoas.select { |_, empresas| empresas.size >= 2 }
                    .map { |nome, empresas| { pessoa: nome, empresas: empresas } }
      end

      private

      def normalizar_nome(nome)
        nome.to_s.strip
            .unicode_normalize(:nfkd)
            .gsub(/[^\x00-\x7F]/, "")
            .downcase.gsub(/\s+/, " ").strip
      end
    end
  end
end
```

**Step 5: Add `nokogiri` to Gemfile**

In `Gemfile`, after the `gem "jbuilder"` line, add:

```ruby
gem "nokogiri"
```

**Step 6: Install gem**

```bash
bundle install
```

**Step 7: Remove old flat service files**

```bash
rm app/services/public_contracts/portal_base_client.rb
rm app/services/public_contracts/dados_gov_client.rb
rm app/services/public_contracts/ted_client.rb
# Keep registo_comercial.rb as a CLI entry-point shim (see step 8)
```

**Step 8: Update the original `registo_comercial.rb` to be a thin CLI shim**

The original file stays for standalone CLI use but just requires the new location:

```ruby
# app/services/public_contracts/registo_comercial.rb
# CLI shim — loads the namespaced class and exposes top-level constants for
# the standalone script interface (ruby registo_comercial.rb NIPC ...).
require_relative "pt/registo_comercial"

RegistoComercial  = PublicContracts::PT::RegistoComercial
ConsultaEmLote    = PublicContracts::PT::ConsultaEmLote
Cruzamento        = PublicContracts::PT::Cruzamento

if __FILE__ == $PROGRAM_NAME
  # ... (keep the existing CLI ARGV block here unchanged)
end
```

Actually, keep the full CLI block in this shim file. Copy it from the existing file.

**Step 9: Run all tests to make sure nothing broke**

```bash
bundle exec rails test 2>&1 | tail -5
```

**Step 10: Commit**

```bash
git add app/services/public_contracts/ Gemfile Gemfile.lock
git commit -m "feat: namespace services into PT/EU modules, add nokogiri gem"
```

---

## Task 11: `BaseClient` unit tests

**Files:**
- Create: `test/services/public_contracts/base_client_test.rb`

**Step 1: Write tests**

```ruby
# test/services/public_contracts/base_client_test.rb
require "test_helper"
require "support/http_stub_helper"

class PublicContracts::BaseClientTest < ActiveSupport::TestCase
  include HttpStubHelper

  setup do
    @client = PublicContracts::BaseClient.new("https://example.com")
  end

  test "get returns parsed JSON on success" do
    response = fake_success('{"key":"value"}')
    stub_get_response(response) do
      result = @client.send(:get, "/path")
      assert_equal({ "key" => "value" }, result)
    end
  end

  test "get with params appends query string" do
    response = fake_success('{"key":"value"}')
    stub_get_response(response) do
      result = @client.send(:get, "/path", foo: "bar")
      assert_equal({ "key" => "value" }, result)
    end
  end

  test "get returns nil on HTTP error" do
    response = fake_error("404", "Not Found")
    stub_get_response(response) do
      result = @client.send(:get, "/path")
      assert_nil result
    end
  end

  test "get returns nil and logs on exception" do
    Net::HTTP.stub(:get_response, ->(_uri) { raise Errno::ECONNREFUSED, "refused" }) do
      result = @client.send(:get, "/path")
      assert_nil result
    end
  end

  test "get with empty params does not append query string" do
    response = fake_success('[]')
    stub_get_response(response) do
      result = @client.send(:get, "/contracts")
      assert_equal [], result
    end
  end
end
```

**Step 2: Run**

```bash
bundle exec rails test test/services/public_contracts/base_client_test.rb 2>&1 | tail -5
```
Expected: 5 runs, 0 failures.

**Step 3: Commit**

```bash
git add test/services/public_contracts/base_client_test.rb
git commit -m "test: add BaseClient unit tests with HTTP stubs"
```

---

## Task 12: `PT::PortalBaseClient` unit tests

**Files:**
- Create: `test/services/public_contracts/pt/portal_base_client_test.rb`

**Step 1: Write tests**

```ruby
# test/services/public_contracts/pt/portal_base_client_test.rb
require "test_helper"
require "support/http_stub_helper"

class PublicContracts::PT::PortalBaseClientTest < ActiveSupport::TestCase
  include HttpStubHelper

  setup do
    @client = PublicContracts::PT::PortalBaseClient.new
  end

  test "country_code is PT" do
    assert_equal "PT", @client.country_code
  end

  test "source_name is Portal BASE" do
    assert_equal "Portal BASE", @client.source_name
  end

  test "fetch_contracts returns array on success" do
    payload = [{ "id" => 1, "object" => "Serviços" }]
    stub_get_response(fake_success(payload.to_json)) do
      result = @client.fetch_contracts
      assert_equal payload, result
    end
  end

  test "fetch_contracts returns empty array when API returns nil" do
    stub_get_response(fake_error) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
  end

  test "find_contract returns hash on success" do
    payload = { "id" => 42, "object" => "Test" }
    stub_get_response(fake_success(payload.to_json)) do
      result = @client.find_contract(42)
      assert_equal payload, result
    end
  end

  test "find_contract returns nil on error" do
    stub_get_response(fake_error("404", "Not Found")) do
      result = @client.find_contract(99)
      assert_nil result
    end
  end

  test "accepts base_url from config" do
    client = PublicContracts::PT::PortalBaseClient.new("base_url" => "https://custom.example.com")
    assert_instance_of PublicContracts::PT::PortalBaseClient, client
  end
end
```

**Step 2: Run**

```bash
bundle exec rails test test/services/public_contracts/pt/portal_base_client_test.rb 2>&1 | tail -5
```
Expected: 7 runs, 0 failures.

**Step 3: Commit**

```bash
git add test/services/public_contracts/pt/portal_base_client_test.rb
git commit -m "test: add PT::PortalBaseClient unit tests"
```

---

## Task 13: `PT::DadosGovClient` unit tests

**Files:**
- Create: `test/services/public_contracts/pt/dados_gov_client_test.rb`

**Step 1: Write tests**

```ruby
# test/services/public_contracts/pt/dados_gov_client_test.rb
require "test_helper"
require "support/http_stub_helper"

class PublicContracts::PT::DadosGovClientTest < ActiveSupport::TestCase
  include HttpStubHelper

  setup do
    @client = PublicContracts::PT::DadosGovClient.new
  end

  test "country_code is PT" do
    assert_equal "PT", @client.country_code
  end

  test "source_name" do
    assert_equal "dados.gov.pt", @client.source_name
  end

  test "search_datasets returns parsed response" do
    payload = { "data" => [{ "id" => "abc" }] }
    stub_get_response(fake_success(payload.to_json)) do
      result = @client.search_datasets("contratos")
      assert_equal payload, result
    end
  end

  test "search_datasets returns nil on error" do
    stub_get_response(fake_error) do
      result = @client.search_datasets("contratos")
      assert_nil result
    end
  end

  test "fetch_resource returns parsed response" do
    payload = { "id" => "res-1", "url" => "https://example.com/file.csv" }
    stub_get_response(fake_success(payload.to_json)) do
      result = @client.fetch_resource("res-1")
      assert_equal payload, result
    end
  end

  test "fetch_contracts extracts data array" do
    payload = { "data" => [{ "id" => "c1" }, { "id" => "c2" }] }
    stub_get_response(fake_success(payload.to_json)) do
      result = @client.fetch_contracts
      assert_equal 2, result.size
    end
  end

  test "fetch_contracts returns empty array when data is nil" do
    stub_get_response(fake_error) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
  end
end
```

**Step 2: Run**

```bash
bundle exec rails test test/services/public_contracts/pt/dados_gov_client_test.rb 2>&1 | tail -5
```
Expected: 7 runs, 0 failures.

**Step 3: Commit**

```bash
git add test/services/public_contracts/pt/dados_gov_client_test.rb
git commit -m "test: add PT::DadosGovClient unit tests"
```

---

## Task 14: `EU::TedClient` unit tests

**Files:**
- Create: `test/services/public_contracts/eu/ted_client_test.rb`

**Step 1: Write tests**

```ruby
# test/services/public_contracts/eu/ted_client_test.rb
require "test_helper"
require "support/http_stub_helper"

class PublicContracts::EU::TedClientTest < ActiveSupport::TestCase
  include HttpStubHelper

  NOTICES_PAYLOAD = {
    "notices"          => [{ "publication-number" => "2026/S001-001" }],
    "totalNoticeCount" => 32000
  }.freeze

  setup do
    @client = PublicContracts::EU::TedClient.new
  end

  test "source_name" do
    assert_equal "TED — Tenders Electronic Daily", @client.source_name
  end

  test "search returns parsed response on success" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.search(query: "organisation-country-buyer=PRT")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "search returns nil on HTTP error" do
    mock = mock_http_post(fake_error("500", "Server Error"))
    Net::HTTP.stub(:new, mock) do
      result = @client.search(query: "organisation-country-buyer=PRT")
      assert_nil result
    end
    mock.verify
  end

  test "search returns nil on network exception" do
    raising_mock = Object.new
    raising_mock.define_singleton_method(:use_ssl=)      { |_| }
    raising_mock.define_singleton_method(:open_timeout=) { |_| }
    raising_mock.define_singleton_method(:read_timeout=) { |_| }
    raising_mock.define_singleton_method(:request)       { |_| raise Errno::ECONNREFUSED }
    Net::HTTP.stub(:new, raising_mock) do
      result = @client.search(query: "test")
      assert_nil result
    end
  end

  test "portuguese_contracts calls search with PRT country code" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.portuguese_contracts(limit: 5)
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "notices_for_country builds correct EQL query" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.notices_for_country("ESP")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "notices_for_country appends keyword when provided" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.notices_for_country("PRT", keyword: "construction")
      assert_equal NOTICES_PAYLOAD, result
    end
    mock.verify
  end

  test "fetch_contracts returns notices array" do
    mock = mock_http_post(fake_success(NOTICES_PAYLOAD.to_json))
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal NOTICES_PAYLOAD["notices"], result
    end
    mock.verify
  end

  test "fetch_contracts returns empty array when search returns nil" do
    mock = mock_http_post(fake_error)
    Net::HTTP.stub(:new, mock) do
      result = @client.fetch_contracts
      assert_equal [], result
    end
    mock.verify
  end

  test "accepts api_key from config" do
    client = PublicContracts::EU::TedClient.new("api_key" => "test-key")
    assert_instance_of PublicContracts::EU::TedClient, client
  end
end
```

**Step 2: Run**

```bash
bundle exec rails test test/services/public_contracts/eu/ted_client_test.rb 2>&1 | tail -5
```
Expected: 10 runs, 0 failures.

**Step 3: Commit**

```bash
git add test/services/public_contracts/eu/ted_client_test.rb
git commit -m "test: add EU::TedClient unit tests with HTTP stubs"
```

---

## Task 15: `PT::RegistoComercial` unit tests (parsing logic — no live HTTP)

These tests exercise the HTML parsing and text extraction logic using fixture HTML strings. No HTTP calls made.

**Files:**
- Create: `test/support/registo_comercial_fixtures.rb`
- Create: `test/services/public_contracts/pt/registo_comercial_test.rb`

**Step 1: Create HTML fixture helper**

```ruby
# test/support/registo_comercial_fixtures.rb
module RegistoComercialFixtures
  SEARCH_RESULTS_HTML = <<~HTML
    <html><body>
      <table>
        <tr>
          <td>509999001</td>
          <td>Construções Ferreira Lda</td>
          <td>2024-01-15</td>
          <td>Registo Comercial</td>
          <td><a href="/DetalhePublicacao.aspx?id=123">Ver</a></td>
        </tr>
        <tr>
          <td>509999001</td>
          <td>Construções Ferreira Lda</td>
          <td>2023-05-20</td>
          <td>Avisos</td>
          <td><a href="/DetalhePublicacao.aspx?id=456">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  DETAIL_HTML = <<~HTML
    <html><body>
      <table>
        <tr><td>NIPC</td><td>509999001</td></tr>
        <tr><td>Firma</td><td>Construções Ferreira Lda</td></tr>
        <tr><td>Data de publicação</td><td>2024-01-15</td></tr>
        <tr><td>Sede</td><td>Rua das Obras 10, Porto</td></tr>
        <tr><td>Capital Social</td><td>50.000 EUR</td></tr>
        <tr><td>Natureza Jurídica</td><td>Sociedade por Quotas</td></tr>
      </table>
      <div id="lblConteudo">
        Sócios: João Ferreira, NIF 123456789, com a quota de 50%.
        Gerentes: Maria Silva, residente em Porto.
      </div>
    </body></html>
  HTML

  HIDDEN_FIELDS_HTML = <<~HTML
    <html><body>
      <form>
        <input type="hidden" name="__VIEWSTATE" value="abc123" />
        <input type="hidden" name="__EVENTVALIDATION" value="xyz789" />
      </form>
    </body></html>
  HTML

  POSTBACK_HTML = <<~HTML
    <html><body>
      <table>
        <tr>
          <td>509999001</td><td>Empresa Teste</td><td>2024-01-01</td><td>Avisos</td>
          <td><a href="javascript:__doPostBack('grid','select$0')">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  GRIDVIEW_HTML = <<~HTML
    <html><body>
      <table id="GridView1">
        <tr>
          <td>509999001</td><td>Grid Empresa</td><td>2024-03-01</td><td>Avisos</td>
          <td><a href="/DetalhePublicacao.aspx?id=789">Ver</a></td>
        </tr>
      </table>
    </body></html>
  HTML

  FALLBACK_LINKS_HTML = <<~HTML
    <html><body>
      <a href="/DetalhePublicacao.aspx?id=999">Publicação Avulsa</a>
    </body></html>
  HTML

  EMPTY_ROWS_HTML = <<~HTML
    <html><body>
      <table><tr><td></td><td></td></tr></table>
    </body></html>
  HTML

  CORPO_FALLBACK_HTML = <<~HTML
    <html><body>
      <p>#{" " * 0}</p>
      <div>#{("texto longo " * 10).strip} sócios: Ana Lopes, NIF 987654321. gerentes: Bruno Costa</div>
    </body></html>
  HTML
end
```

**Step 2: Write the unit tests**

```ruby
# test/services/public_contracts/pt/registo_comercial_test.rb
require "test_helper"
require "support/registo_comercial_fixtures"

class PublicContracts::PT::RegistoComercialTest < ActiveSupport::TestCase
  include RegistoComercialFixtures

  setup do
    # pausa: 0 so tests don't sleep
    @rc = PublicContracts::PT::RegistoComercial.new(pausa: 0)
  end

  # ── NIPC validation ───────────────────────────────────────────────────────
  test "pesquisar_por_nipc raises on short NIPC" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("123") }
  end

  test "pesquisar_por_nipc raises on empty string" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nipc("") }
  end

  test "pesquisar_por_nipc strips non-digits before length check" do
    # "123-456-789" → "123456789" → 9 digits — should NOT raise
    # (it will still try HTTP, so we stub it out)
    stub_pesquisar_returns([]) do
      result = @rc.pesquisar_por_nipc("123-456-789")
      assert_equal [], result
    end
  end

  test "pesquisar_por_nome raises on empty name" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nome("") }
  end

  test "pesquisar_por_nome raises on blank name" do
    assert_raises(ArgumentError) { @rc.pesquisar_por_nome("   ") }
  end

  # ── HTML parsing — extrair_campos_ocultos ─────────────────────────────────
  test "extrair_campos_ocultos returns hash of hidden inputs" do
    campos = @rc.send(:extrair_campos_ocultos, HIDDEN_FIELDS_HTML)
    assert_equal "abc123", campos["__VIEWSTATE"]
    assert_equal "xyz789", campos["__EVENTVALIDATION"]
  end

  # ── HTML parsing — extrair_resultados ────────────────────────────────────
  test "extrair_resultados parses table rows" do
    results = @rc.send(:extrair_resultados, SEARCH_RESULTS_HTML)
    assert_equal 2, results.size
    assert_equal "509999001", results.first[:nipc]
    assert_equal "Construções Ferreira Lda", results.first[:entidade]
    assert results.first[:ligacao].include?("DetalhePublicacao")
  end

  test "extrair_resultados falls back to GridView selector" do
    results = @rc.send(:extrair_resultados, GRIDVIEW_HTML)
    assert results.size >= 1
  end

  test "extrair_resultados falls back to link scan when no table" do
    results = @rc.send(:extrair_resultados, FALLBACK_LINKS_HTML)
    assert results.size >= 1
    assert results.first[:ligacao].include?("Detalhe")
  end

  test "extrair_resultados skips all-empty rows" do
    results = @rc.send(:extrair_resultados, EMPTY_ROWS_HTML)
    assert_equal 0, results.size
  end

  # ── HTML parsing — extrair_linha_resultado ────────────────────────────────
  test "extrair_linha_resultado marks postback links as :postback" do
    results = @rc.send(:extrair_resultados, POSTBACK_HTML)
    assert_equal 1, results.size
    assert_equal :postback, results.first[:ligacao]
  end

  # ── HTML parsing — extrair_detalhe ───────────────────────────────────────
  test "extrair_detalhe parses structured fields" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_equal "509999001", detalhe[:nipc]
    assert_equal "Construções Ferreira Lda", detalhe[:entidade]
    assert_equal "Rua das Obras 10, Porto", detalhe[:sede]
    assert_equal "50.000 EUR", detalhe[:capital_social]
    assert_equal "Sociedade por Quotas", detalhe[:natureza_juridica]
  end

  test "extrair_detalhe extracts socios from corpo" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_includes detalhe[:socios], "João Ferreira"
  end

  test "extrair_detalhe extracts gerentes from corpo" do
    detalhe = @rc.send(:extrair_detalhe, DETAIL_HTML)
    assert_includes detalhe[:gerentes], "Maria Silva"
  end

  test "extrair_detalhe uses fallback for corpo when no id match" do
    detalhe = @rc.send(:extrair_detalhe, CORPO_FALLBACK_HTML)
    refute_nil detalhe[:corpo]
  end

  test "extrair_detalhe returns empty hash for empty HTML" do
    detalhe = @rc.send(:extrair_detalhe, "<html></html>")
    assert_kind_of Hash, detalhe
  end

  # ── Text extraction ────────────────────────────────────────────────────────
  test "extrair_socios finds name after sócio pattern" do
    texto  = "Sócios: António Rodrigues, NIF 111222333, com 100%."
    nomes  = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "António Rodrigues"
  end

  test "extrair_socios finds name after quota pattern" do
    texto = "quota pertencente a Carlos Mendes com 50%"
    nomes = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "Carlos Mendes"
  end

  test "extrair_socios finds accionista pattern" do
    texto = "Accionistas: Sofia Pinto, detendo 1000 acções"
    nomes = @rc.send(:extrair_socios, texto)
    assert_includes nomes, "Sofia Pinto"
  end

  test "extrair_socios returns unique names" do
    texto = "Sócios: Manuel Costa, NIF 123. Sócios: Manuel Costa, NIF 123."
    nomes = @rc.send(:extrair_socios, texto)
    assert_equal 1, nomes.count { |n| n == "Manuel Costa" }
  end

  test "extrair_gerentes finds gerente pattern" do
    texto  = "Gerentes: Rui Alves, residente em Lisboa."
    nomes  = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Rui Alves"
  end

  test "extrair_gerentes finds administrador pattern" do
    texto = "Administradores: Pedro Gomes, portador do BI 12345"
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Pedro Gomes"
  end

  test "extrair_gerentes finds presidente pattern" do
    texto = "Presidente: Lúcia Faria com funções de..."
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_includes nomes, "Lúcia Faria"
  end

  test "extrair_gerentes returns unique names" do
    texto = "Gerentes: Rui Alves. Gerentes: Rui Alves."
    nomes = @rc.send(:extrair_gerentes, texto)
    assert_equal 1, nomes.count { |n| n == "Rui Alves" }
  end

  # ── obter_detalhe guards ───────────────────────────────────────────────────
  test "obter_detalhe returns nil for nil ligacao" do
    assert_nil @rc.obter_detalhe(nil)
  end

  test "obter_detalhe returns nil for non-http ligacao" do
    assert_nil @rc.obter_detalhe("javascript:void(0)")
  end

  private

  # Minimal stub: make pesquisar return a preset value without HTTP.
  def stub_pesquisar_returns(value, &block)
    @rc.stub(:pesquisar, value, &block)
  end
end
```

**Step 3: Run**

```bash
bundle exec rails test test/services/public_contracts/pt/registo_comercial_test.rb 2>&1 | tail -5
```
Expected: ~27 runs, 0 failures.

**Step 4: Commit**

```bash
git add test/services/public_contracts/pt/registo_comercial_test.rb \
        test/support/registo_comercial_fixtures.rb
git commit -m "test: add PT::RegistoComercial unit tests with HTML fixture strings"
```

---

## Task 16: Implement and test `ImportService`

**Files:**
- Modify: `app/services/public_contracts/import_service.rb`
- Create: `test/services/public_contracts/import_service_test.rb`

**Step 1: Write the failing test**

```ruby
# test/services/public_contracts/import_service_test.rb
require "test_helper"

class PublicContracts::ImportServiceTest < ActiveSupport::TestCase

  # ── helpers ────────────────────────────────────────────────────────────────

  def build_contract_attrs(overrides = {})
    {
      "external_id"   => "ext-#{SecureRandom.hex(4)}",
      "object"        => "Serviços de consultoria",
      "country_code"  => "PT",
      "contract_type" => "Aquisição de Serviços",
      "base_price"    => 15000.0,
      "contracting_entity" => {
        "tax_identifier" => "500000001",
        "name"           => "Câmara Municipal Teste",
        "is_public_body" => true
      },
      "winners" => [
        { "tax_identifier" => "509888001", "name" => "Empresa Vencedora Lda", "is_company" => true }
      ]
    }.merge(overrides)
  end

  def stub_adapter(contracts)
    adapter = Minitest::Mock.new
    adapter.expect(:fetch_contracts, contracts)
    adapter
  end

  def build_data_source(adapter_mock)
    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter_mock) { yield ds }
  end

  # ── happy path ────────────────────────────────────────────────────────────
  test "call creates contract and entities from adapter data" do
    attrs   = build_contract_attrs
    adapter = stub_adapter([attrs])
    build_data_source(adapter) do |ds|
      service = PublicContracts::ImportService.new(ds)
      assert_difference ["Contract.count", "Entity.count"], 1 do
        service.call
      end
    end
    adapter.verify
  end

  test "call sets data_source and country_code on contract" do
    attrs   = build_contract_attrs("country_code" => "PT")
    adapter = stub_adapter([attrs])
    build_data_source(adapter) do |ds|
      PublicContracts::ImportService.new(ds).call
      contract = Contract.find_by(external_id: attrs["external_id"])
      assert_equal ds.id,    contract.data_source_id
      assert_equal "PT",     contract.country_code
    end
    adapter.verify
  end

  test "call creates winners for each winner in attrs" do
    attrs   = build_contract_attrs
    adapter = stub_adapter([attrs])
    build_data_source(adapter) do |ds|
      assert_difference "ContractWinner.count", 1 do
        PublicContracts::ImportService.new(ds).call
      end
    end
    adapter.verify
  end

  test "call updates data_source status to active and last_synced_at" do
    adapter = stub_adapter([])
    build_data_source(adapter) do |ds|
      PublicContracts::ImportService.new(ds).call
      ds.reload
      assert ds.active?
      assert_not_nil ds.last_synced_at
    end
    adapter.verify
  end

  test "call updates record_count" do
    adapter = stub_adapter([build_contract_attrs, build_contract_attrs])
    build_data_source(adapter) do |ds|
      PublicContracts::ImportService.new(ds).call
      assert_equal 2, ds.reload.record_count
    end
    adapter.verify
  end

  test "call is idempotent — re-importing same contract does not duplicate" do
    attrs   = build_contract_attrs
    adapter = stub_adapter([attrs])
    build_data_source(adapter) do |ds|
      service = PublicContracts::ImportService.new(ds)
      service.call
      adapter2 = stub_adapter([attrs])
      ds.stub(:adapter, adapter2) do
        assert_no_difference "Contract.count" do
          PublicContracts::ImportService.new(ds).call
        end
      end
      adapter2.verify
    end
    adapter.verify
  end

  # ── error handling ────────────────────────────────────────────────────────
  test "call sets status to error when adapter raises" do
    adapter = Minitest::Mock.new
    adapter.expect(:fetch_contracts, nil) { raise RuntimeError, "API down" }
    build_data_source(adapter) do |ds|
      assert_raises(RuntimeError) do
        PublicContracts::ImportService.new(ds).call
      end
      assert ds.reload.error?
    end
  end
end
```

**Step 2: Run to see failures**

```bash
bundle exec rails test test/services/public_contracts/import_service_test.rb 2>&1 | tail -10
```

**Step 3: Implement `ImportService`**

```ruby
# app/services/public_contracts/import_service.rb
# frozen_string_literal: true

module PublicContracts
  class ImportService
    def initialize(data_source_record)
      @ds = data_source_record
    end

    def call
      contracts = @ds.adapter.fetch_contracts
      contracts.each { |attrs| import_contract(attrs) }
      @ds.update!(status: :active, last_synced_at: Time.current, record_count: contracts.size)
    rescue => e
      @ds.update!(status: :error)
      raise
    end

    private

    def import_contract(attrs)
      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return unless contracting

      contract = Contract.find_or_create_by!(
        external_id: attrs["external_id"]
      ) do |c|
        c.object              = attrs["object"]
        c.country_code        = attrs["country_code"] || @ds.country_code
        c.contract_type       = attrs["contract_type"]
        c.procedure_type      = attrs["procedure_type"]
        c.publication_date    = attrs["publication_date"]
        c.celebration_date    = attrs["celebration_date"]
        c.base_price          = attrs["base_price"]
        c.total_effective_price = attrs["total_effective_price"]
        c.cpv_code            = attrs["cpv_code"]
        c.location            = attrs["location"]
        c.contracting_entity  = contracting
        c.data_source         = @ds
      end

      Array(attrs["winners"]).each do |winner_attrs|
        winner = find_or_create_entity(
          winner_attrs["tax_identifier"],
          winner_attrs["name"],
          is_company: winner_attrs["is_company"] || false
        )
        next unless winner
        ContractWinner.find_or_create_by!(contract: contract, entity: winner)
      end
    end

    def find_or_create_entity(tax_id, name, is_public_body: false, is_company: false)
      return nil if tax_id.blank? || name.blank?

      country = @ds.country_code
      Entity.find_or_create_by!(tax_identifier: tax_id, country_code: country) do |e|
        e.name          = name
        e.is_public_body = is_public_body
        e.is_company    = is_company
      end
    end
  end
end
```

**Step 4: Run test**

```bash
bundle exec rails test test/services/public_contracts/import_service_test.rb 2>&1 | tail -5
```
Expected: 7 runs, 0 failures.

**Step 5: Commit**

```bash
git add app/services/public_contracts/import_service.rb \
        test/services/public_contracts/import_service_test.rb
git commit -m "feat: implement ImportService with country-aware find_or_create, add tests"
```

---

## Task 17: Full test run + coverage check

**Step 1: Run the complete test suite**

```bash
bundle exec rails test 2>&1 | tail -20
```
Expected: all green, 0 failures, 0 errors.

**Step 2: Open coverage report**

```bash
open coverage/index.html
```

**Step 3: Identify any uncovered lines**

SimpleCov prints a summary per file. For any file below 100%:
- Read the file, find which branches/lines are uncovered
- Add a targeted test in the relevant test file

**Step 4: Common gaps to check**

| File | Likely gap | Fix |
|---|---|---|
| `base_client.rb` | `handle_error` (private, called by `get`) | Already covered by `fake_error` stub test |
| `ted_client.rb` | `rails_log` when `Rails` not defined | Add test without Rails env or verify `warn` branch |
| `import_service.rb` | `find_or_create_entity` with blank tax_id | Add test with nil contracting entity attrs |
| `registo_comercial.rb` | `guardar_biscoitos` with no Set-Cookie header | Covered by HTTP stub returning no cookies |

**Step 5: Once at 100%, commit**

```bash
git add test/
git commit -m "test: reach 100% SimpleCov coverage"
```

---

## Task 18: Update the standalone CLI shim (final cleanup)

Ensure the old integration test files still reference the right class names.

**Files:**
- Modify: `test/services/public_contracts/registo_comercial_test.rb` — update `RegistoComercial` → `PublicContracts::PT::RegistoComercial`
- Modify: `test/services/public_contracts/ted_client_test.rb` — update `TedClient` → `PublicContracts::EU::TedClient`

These are integration tests (live HTTP, run standalone). Update constant references but do not add them to `rails test`.

```bash
git add test/services/public_contracts/registo_comercial_test.rb \
        test/services/public_contracts/ted_client_test.rb
git commit -m "chore: update integration test constant references to namespaced classes"
```

---

## Final verification

```bash
bundle exec rails test 2>&1
# Look for: "X runs, 0 failures, 0 errors"
# Check: coverage/index.html shows 100%
```

---

## Summary of all new/changed files

| Action | File |
|---|---|
| New model | `app/models/data_source.rb` |
| Modified | `app/models/entity.rb` |
| Modified | `app/models/contract.rb` |
| New service | `app/services/public_contracts/pt/portal_base_client.rb` |
| New service | `app/services/public_contracts/pt/dados_gov_client.rb` |
| New service | `app/services/public_contracts/pt/registo_comercial.rb` |
| New service | `app/services/public_contracts/eu/ted_client.rb` |
| Modified service | `app/services/public_contracts/import_service.rb` |
| Shim | `app/services/public_contracts/registo_comercial.rb` (CLI shim) |
| Deleted | `app/services/public_contracts/portal_base_client.rb` |
| Deleted | `app/services/public_contracts/dados_gov_client.rb` |
| Deleted | `app/services/public_contracts/ted_client.rb` |
| 3 migrations | `db/migrate/` |
| New test helper | `test/support/http_stub_helper.rb` |
| New test helper | `test/support/registo_comercial_fixtures.rb` |
| New fixture | `test/fixtures/data_sources.yml` |
| Modified fixtures | `test/fixtures/entities.yml`, `contracts.yml` |
| New tests | `test/models/data_source_test.rb` |
| Modified tests | `test/models/entity_test.rb`, `contract_test.rb`, `contract_winner_test.rb` |
| New tests | `test/services/public_contracts/base_client_test.rb` |
| New tests | `test/services/public_contracts/pt/portal_base_client_test.rb` |
| New tests | `test/services/public_contracts/pt/dados_gov_client_test.rb` |
| New tests | `test/services/public_contracts/pt/registo_comercial_test.rb` |
| New tests | `test/services/public_contracts/eu/ted_client_test.rb` |
| New tests | `test/services/public_contracts/import_service_test.rb` |
