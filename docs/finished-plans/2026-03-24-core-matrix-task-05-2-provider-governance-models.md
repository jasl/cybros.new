# Core Matrix Task 05.2: Add Provider Governance Models And Services

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`

Load this file as the detailed execution unit for Task 05.2. Treat Task Group 05 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
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
- Create: `core_matrix/test/services/provider_credentials/upsert_secret_test.rb`
- Create: `core_matrix/test/services/provider_entitlements/upsert_test.rb`
- Create: `core_matrix/test/services/provider_policies/upsert_test.rb`
- Create: `core_matrix/test/integration/provider_governance_flow_test.rb`

**Step 1: Write failing model, service, and integration tests**

Cover at least:

- credential secrecy behavior
- entitlement window kinds including rolling five-hour windows
- policy enablement and throttling fields
- persisting a provider credential and entitlement against catalog keys
- persisting or updating a provider policy through a service boundary
- rejecting governance rows that point at unknown provider references
- audit rows for provider credential, entitlement, and policy changes

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_entitlements/upsert_test.rb test/services/provider_policies/upsert_test.rb test/integration/provider_governance_flow_test.rb
```

Expected:

- missing table, model, or service failures

**Step 3: Write migrations, models, and services**

Rules:

- store only credentials, entitlements, and policies in relational tables
- governance rows must point at known catalog entries instead of inventing provider-model SQL tables
- govern credential, entitlement, and policy mutations through explicit services so audit logging is deterministic
- provider credential, entitlement, and policy mutations must create audit rows

**Step 4: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_entitlements/upsert_test.rb test/services/provider_policies/upsert_test.rb test/integration/provider_governance_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models/provider_credential.rb core_matrix/app/models/provider_entitlement.rb core_matrix/app/models/provider_policy.rb core_matrix/app/services/provider_credentials core_matrix/app/services/provider_entitlements core_matrix/app/services/provider_policies core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add provider governance models"
```

## Stop Point

Stop after provider governance models and audited mutation services pass their tests.

Do not implement these items in this task:

- provider usage events
- execution profiling facts
- runtime model selection logic

## Completion Record

- status:
  completed on `2026-03-24`
- actual landed scope:
  - added installation-scoped `ProviderCredential`,
    `ProviderEntitlement`, and `ProviderPolicy` tables
  - added audited upsert services for provider credentials, entitlements, and
    policies
  - anchored governance rows to Task 05.1 catalog provider handles instead of
    introducing provider/model SQL catalog tables
  - added `core_matrix/docs/behavior/provider-governance-models-and-services.md`
  - added targeted model, service, and integration coverage for secrecy,
    rolling-window entitlements, policy throttling, catalog-key validation, and
    audit logging
- plan alignment notes:
  - the task stayed within governance-row scope and did not pre-implement usage
    events, profiling facts, or execution-time selector logic
  - secret material uses Rails Active Record Encryption, while provider
    selection identity remains catalog-backed and explicit
- verification evidence:
  - `cd core_matrix && bin/rails test test/models/provider_credential_test.rb test/models/provider_entitlement_test.rb test/models/provider_policy_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_entitlements/upsert_test.rb test/services/provider_policies/upsert_test.rb test/integration/provider_governance_flow_test.rb`
    passed with `13 runs, 52 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is an installation-governance data surface already covered by
    automated tests
- retained findings:
  - provider governance facts belong in relational tables, but provider/model
    catalog identity should stay config-backed and be referenced by key
  - rolling five-hour entitlements are clearer when both the semantic
    `window_kind` and the derived `window_seconds` are persisted explicitly
  - reference sanity check from
    `references/original/references/dify/api/services/entities/model_provider_entities.py`
    and
    `references/original/references/openclaw/src/node-host/runner.credentials.test.ts`:
    keep volatile provider catalog metadata separate from secret-bearing
    configuration state
- carry-forward notes:
  - Task 06.1 should treat entitlement rows as installation-governance facts
    and build usage events and rollups around them instead of folding quota
    state into the provider catalog
  - later selector-resolution work should consult provider policy enablement,
    credential availability, and entitlement availability without mutating the
    catalog itself
