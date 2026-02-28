# Codex Branch Audit — 2026-02-27

## Branch A — `codex/implement-full-ingestion-for-portal-base`
- **Status**: NEEDS FIX
- **Objetivo**: Ingestão completa do Portal BASE (Issue #6).
- **Rebase em `upstream/master`**: concluído com `git rebase -X theirs upstream/master`.
- **Conflitos identificados durante tentativa de rebase padrão**:
  - `app/services/public_contracts/import_service.rb`
  - `db/schema.rb`
  - `test/fixtures/data_sources.yml`
  - `test/services/public_contracts/import_service_test.rb`
- **Foco**: não contém ficheiros de flags, mas inclui alterações de README/Gemfile para ingestão.
- **Risco/impacto**:
  - `db/schema.rb` regressa a `version: 2026_02_27_090000` mas mantém tabela `flags`, gerando migração pendente duplicada no ambiente local.
  - `bundle exec rails test` executa testes sem falhas funcionais, mas falha gate de cobertura (99.05% < 100%).
- **Comandos obrigatórios**:

```bash
git rev-list --left-right --count upstream/master...HEAD
0	2
```

```bash
git diff --name-only upstream/master...HEAD
Gemfile
Gemfile.lock
README.md
README.pt.md
app/jobs/portal_base/enqueue_full_ingestion_job.rb
app/jobs/portal_base/ingest_data_source_job.rb
app/jobs/portal_base/ingest_page_job.rb
app/models/data_source.rb
app/services/import_service.rb
app/services/public_contracts/import_service.rb
app/services/public_contracts/pt/portal_base_client.rb
config/queue.yml
db/migrate/20260227090000_add_portal_base_ingestion_tracking.rb
db/schema.rb
lib/tasks/portal_base.rake
test/fixtures/data_sources.yml
test/jobs/portal_base/enqueue_full_ingestion_job_test.rb
test/jobs/portal_base/ingest_data_source_job_test.rb
test/jobs/portal_base/ingest_page_job_test.rb
test/models/contract_test.rb
test/services/public_contracts/eu/ted_client_test.rb
test/services/public_contracts/import_service_test.rb
test/services/public_contracts/pt/portal_base_client_test.rb
test/test_helper.rb
```

```bash
Resultado de bundle exec rails test
257 runs, 450 assertions, 0 failures, 0 errors, 0 skips
Line coverage (99.05%) is below the expected minimum coverage (100.00%).
```

- **Pronto para PR?** NÃO.

## Branch B — `codex/add-flag-model-and-flagservice-base-class`
- **Status**: NEEDS FIX
- **Objetivo**: fundação de flags (Issue #10).
- **Rebase em `upstream/master`**: concluído com `git rebase -X theirs upstream/master`.
- **Conflitos identificados durante tentativa de rebase padrão**:
  - `app/services/public_contracts/import_service.rb`
  - `db/schema.rb`
  - `test/fixtures/data_sources.yml`
  - `test/services/public_contracts/eu/ted_client_test.rb`
  - `test/services/public_contracts/import_service_test.rb`
- **Foco**: **misturado** (ingestão Portal BASE + docs/templates + flags).
- **Risco/impacto**:
  - Inclui duplicação de migração `CreateFlags` (`20260227103000_create_flags.rb`) face ao upstream (`20260227191500_create_flags.rb`).
  - Testes nem arrancam: `ActiveRecord::DuplicateMigrationNameError`.
- **Comandos obrigatórios**:

```bash
git rev-list --left-right --count upstream/master...HEAD
0	6
```

```bash
git diff --name-only upstream/master...HEAD
.github/pull_request_template.md
AGENTS.md
Gemfile
Gemfile.lock
README.md
README.pt.md
app/jobs/portal_base/enqueue_full_ingestion_job.rb
app/jobs/portal_base/ingest_data_source_job.rb
app/jobs/portal_base/ingest_page_job.rb
app/models/contract.rb
app/models/data_source.rb
app/models/flag.rb
app/services/flags/base_service.rb
app/services/import_service.rb
app/services/public_contracts/import_service.rb
app/services/public_contracts/pt/portal_base_client.rb
config/queue.yml
db/migrate/20260227090000_add_portal_base_ingestion_tracking.rb
db/migrate/20260227103000_create_flags.rb
db/schema.rb
docs/plans/AI_GUIDE.md
lib/tasks/portal_base.rake
test/fixtures/contracts.yml
test/fixtures/data_sources.yml
test/fixtures/entities.yml
test/jobs/portal_base/enqueue_full_ingestion_job_test.rb
test/jobs/portal_base/ingest_data_source_job_test.rb
test/jobs/portal_base/ingest_page_job_test.rb
test/models/contract_test.rb
test/models/flag_test.rb
test/services/flags/base_service_test.rb
test/services/public_contracts/eu/ted_client_test.rb
test/services/public_contracts/import_service_test.rb
test/services/public_contracts/pt/portal_base_client_test.rb
test/test_helper.rb
```

```bash
Resultado de bundle exec rails test
Falhou antes dos testes com ActiveRecord::DuplicateMigrationNameError
Multiple migrations have the name CreateFlags.
```

- **Pronto para PR?** NÃO.

## Branch C — `codex/implement-full-ingestion-for-portal-base-ol6wx5`
- **Status**: DISCARD (como PR direto)
- **Objetivo**: superconjunto de ingestão com hardening e docs operacionais.
- **Rebase em `upstream/master`**: concluído com `git rebase -X theirs upstream/master`.
- **Conflitos reportados**: nenhum durante este rebase.
- **Comparação com Branch A**:
  - C inclui commit extra de documentação operacional (`Refine snapshot ingestion documentation and troubleshooting`).
  - No conteúdo após rebase, diferenças diretas A↔C concentradas em:
    - `app/services/public_contracts/import_service.rb`
    - `test/models/contract_test.rb`
- **Risco/impacto**:
  - Não é PR direto ideal: mistura ingestão + documentação de troubleshooting.
  - Mesmo problema de migração pendente (schema version desalinhada com `CreateFlags` do upstream).
- **Comandos obrigatórios**:

```bash
git rev-list --left-right --count upstream/master...HEAD
0	3
```

```bash
git diff --name-only upstream/master...HEAD
Gemfile
Gemfile.lock
README.md
README.pt.md
app/jobs/portal_base/enqueue_full_ingestion_job.rb
app/jobs/portal_base/ingest_data_source_job.rb
app/jobs/portal_base/ingest_page_job.rb
app/models/data_source.rb
app/services/import_service.rb
app/services/public_contracts/import_service.rb
app/services/public_contracts/pt/portal_base_client.rb
config/queue.yml
db/migrate/20260227090000_add_portal_base_ingestion_tracking.rb
db/schema.rb
lib/tasks/portal_base.rake
test/fixtures/data_sources.yml
test/jobs/portal_base/enqueue_full_ingestion_job_test.rb
test/jobs/portal_base/ingest_data_source_job_test.rb
test/jobs/portal_base/ingest_page_job_test.rb
test/models/contract_test.rb
test/services/public_contracts/eu/ted_client_test.rb
test/services/public_contracts/import_service_test.rb
test/services/public_contracts/pt/portal_base_client_test.rb
test/test_helper.rb
```

```bash
Resultado de bundle exec rails test
Falhou com migração pendente:
You have 1 pending migration: db/migrate/20260227191500_create_flags.rb
```

- **Pronto para PR?** NÃO (usar cherry-pick seletivo para A).

## Recomendações de PR para upstream/master
1. **Issue #6 (Branch A)**
   - Criar PR apenas após corrigir:
     - `db/schema.rb` version para não deixar migração pendente;
     - cobertura para 100%.
   - Body sugerido:
     - `Closes #6`
     - Ingestão completa Portal BASE (jobs, paginação full, checkpoint recovery, tarefas operacionais e testes).

2. **Issue #10 (Branch B)**
   - Não abrir PR desta branch no estado atual.
   - Recriar branch a partir de `upstream/master` contendo apenas foundation de flags (sem ingestão/docs/templates) e sem migração duplicada.
   - Body sugerido:
     - `Closes #10`
     - Introduz base de execução de flags e testes, sem alterações de ingestão.

3. **Branch C**
   - Não usar para PR direto.
   - Estratégia recomendada: partir da A e fazer **cherry-pick seletivo** apenas de hardening útil de `import_service` + respetivos testes, descartando commits de docs/ruído.
