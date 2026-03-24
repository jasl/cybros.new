# Core Matrix Kernel Phase 2: Governance And Accounting

Use this phase document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 5-6:

- config-backed provider catalog, governance models, and role-based model selection catalog
- usage accounting, rollups, and execution profiling facts

Apply the shared guardrails and phase-gate audits from the implementation-plan index.

---
### Task 5: Build The Config-Backed Provider Catalog And Governance Models

**Files:**
- Create: `core_matrix/config/providers/catalog.yml`
- Create: `core_matrix/app/services/provider_catalog/load.rb`
- Create: `core_matrix/app/services/provider_catalog/validate.rb`
- Create: `core_matrix/db/migrate/20260324090013_create_provider_credentials.rb`
- Create: `core_matrix/db/migrate/20260324090014_create_provider_entitlements.rb`
- Create: `core_matrix/db/migrate/20260324090015_create_provider_policies.rb`
- Create: `core_matrix/app/models/provider_credential.rb`
- Create: `core_matrix/app/models/provider_entitlement.rb`
- Create: `core_matrix/app/models/provider_policy.rb`
- Create: `core_matrix/app/services/provider_credentials/upsert_secret.rb`
- Create: `core_matrix/app/services/provider_entitlements/upsert.rb`
- Create: `core_matrix/app/services/provider_policies/upsert.rb`
- Create: `core_matrix/test/models/provider_credential_test.rb`
- Create: `core_matrix/test/models/provider_entitlement_test.rb`
- Create: `core_matrix/test/models/provider_policy_test.rb`
- Create: `core_matrix/test/services/provider_catalog/load_test.rb`
- Create: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Create: `core_matrix/test/services/provider_credentials/upsert_secret_test.rb`
- Create: `core_matrix/test/services/provider_entitlements/upsert_test.rb`
- Create: `core_matrix/test/services/provider_policies/upsert_test.rb`
- Create: `core_matrix/test/integration/provider_catalog_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- catalog loading from config
- schema validation for provider key, model key, capabilities, and metadata shape
- schema validation for ordered model-role candidate lists in `provider_handle/model_ref` form
- schema validation for multimodal input capability flags such as image, audio, video, and file or document support
- credential secrecy behavior
- entitlement window kinds including rolling five-hour windows
- policy enablement and throttling fields
- audit rows for provider credential, entitlement, and policy changes

**Step 2: Write a failing integration flow test**

`provider_catalog_flow_test.rb` should cover:

- loading the catalog at boot
- loading role-catalog entries such as `main` and `coder`
- persisting a provider credential and entitlement against catalog keys
- persisting or updating a provider policy through a service boundary
- rejecting governance rows that point at unknown provider references
- rejecting role-catalog entries that point at unknown `provider_handle/model_ref` values
- writing audit rows for credential, entitlement, and policy mutations

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_entitlements/upsert_test.rb test/services/provider_policies/upsert_test.rb test/integration/provider_catalog_flow_test.rb
```

Expected:

- missing file, model, or validation failures

**Step 4: Write catalog files, models, and services**

Rules:

- keep provider and model catalog data in config, not SQL
- keep model-role candidate ordering in config next to the provider catalog, not in SQL
- store only credentials, entitlements, and policies in relational tables
- preserve model capabilities, context-window metadata, and display metadata from config
- preserve explicit multimodal input capability metadata so later workflow context assembly can gate attachment projection without guessing
- preserve ordered role candidate lists such as `main`, `planner`, and `coder`
- validate every role candidate against known provider and model references
- govern credential, entitlement, and policy mutations through explicit services so audit logging is deterministic
- provider credential, entitlement, and policy mutations must create audit rows

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_entitlements/upsert_test.rb test/services/provider_policies/upsert_test.rb test/integration/provider_catalog_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/config/providers core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/provider_catalog core_matrix/app/services/provider_credentials core_matrix/app/services/provider_entitlements core_matrix/app/services/provider_policies core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add provider catalog and governance foundations"
```

### Task 6: Build Usage Accounting, Rollups, And Execution Profiling Facts

**Files:**
- Create: `core_matrix/db/migrate/20260324090016_create_usage_events.rb`
- Create: `core_matrix/db/migrate/20260324090017_create_usage_rollups.rb`
- Create: `core_matrix/db/migrate/20260324090018_create_execution_profile_facts.rb`
- Create: `core_matrix/app/models/usage_event.rb`
- Create: `core_matrix/app/models/usage_rollup.rb`
- Create: `core_matrix/app/models/execution_profile_fact.rb`
- Create: `core_matrix/app/services/provider_usage/record_event.rb`
- Create: `core_matrix/app/services/provider_usage/project_rollups.rb`
- Create: `core_matrix/app/services/execution_profiling/record_fact.rb`
- Create: `core_matrix/test/models/usage_event_test.rb`
- Create: `core_matrix/test/models/usage_rollup_test.rb`
- Create: `core_matrix/test/models/execution_profile_fact_test.rb`
- Create: `core_matrix/test/services/provider_usage/record_event_test.rb`
- Create: `core_matrix/test/services/provider_usage/project_rollups_test.rb`
- Create: `core_matrix/test/services/execution_profiling/record_fact_test.rb`
- Create: `core_matrix/test/integration/runtime_accounting_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- usage events carrying user, workspace, conversation, turn, workflow node, provider, model, and operation dimensions
- rollup uniqueness by bucket and dimensions
- execution profile facts for tool calls, subagent outcomes, approval wait time, and process failures
- support for token-based and media-unit usage

**Step 2: Write a failing integration flow test**

`runtime_accounting_flow_test.rb` should cover:

- recording a usage event
- projecting hourly and daily rollups
- recording separate execution profile facts without polluting provider usage rows

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/models/execution_profile_fact_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/runtime_accounting_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Include:

- rollup rows keyed by hour, day, and explicit rolling-window identifiers
- profile facts separated from provider billing facts
- global hard-limit support without per-user enforced quotas

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/usage_event_test.rb test/models/usage_rollup_test.rb test/models/execution_profile_fact_test.rb test/services/provider_usage/record_event_test.rb test/services/provider_usage/project_rollups_test.rb test/services/execution_profiling/record_fact_test.rb test/integration/runtime_accounting_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/provider_usage core_matrix/app/services/execution_profiling core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add usage accounting and profiling facts"
```
