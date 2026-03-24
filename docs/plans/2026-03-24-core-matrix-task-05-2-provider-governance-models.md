# Core Matrix Task 05.2: Add Provider Governance Models And Services

Part of `Core Matrix Kernel Phase 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`

Load this file as the detailed execution unit for Task 05.2. Treat Task 05 and the phase file as ordering indexes, not as the full task body.

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

Do not implement these items in this subtask:

- provider usage events
- execution profiling facts
- runtime model selection logic
