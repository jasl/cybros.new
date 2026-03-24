# Core Matrix Task 05.1: Add Provider Catalog Config And Validation

Part of `Core Matrix Kernel Milestone 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/finished-plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/finished-plans/2026-03-24-core-matrix-kernel-milestone-2-governance-and-accounting.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 05.1. Treat Task Group 05 and the milestone file as ordering indexes, not as the full task body.

Reference capture for this task:

- if this task consults `references/` or external implementations, record the consulted slice and the retained conclusion, invariant, or intentional difference in this task document or another local document updated by the same execution unit
- when this task updates behavior docs, checklist docs, or other local docs, carry that conclusion into those docs instead of leaving only a bare reference path
- keep reference paths as index pointers only; restate the relevant behavior locally so this task remains understandable if the reference later drifts

---

**Files:**
- Create: `core_matrix/config/providers/catalog.yml`
- Create: `core_matrix/app/services/provider_catalog/load.rb`
- Create: `core_matrix/app/services/provider_catalog/validate.rb`
- Create: `core_matrix/test/services/provider_catalog/load_test.rb`
- Create: `core_matrix/test/services/provider_catalog/validate_test.rb`
- Create: `core_matrix/test/integration/provider_catalog_boot_flow_test.rb`

**Step 1: Write failing service and integration tests**

Cover at least:

- catalog loading from config
- schema validation for provider key, model key, capabilities, and metadata shape
- schema validation for ordered model-role candidate lists in `provider_handle/model_ref` form
- schema validation for multimodal input capability flags such as image, audio, video, and file or document support
- loading role-catalog entries such as `main` and `coder`
- rejecting role-catalog entries that point at unknown `provider_handle/model_ref` values

**Step 2: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- missing file or validation failures

**Step 3: Write catalog files and services**

Rules:

- keep provider and model catalog data in config, not SQL
- keep model-role candidate ordering in config next to the provider catalog, not in SQL
- preserve model capabilities, context-window metadata, and display metadata from config
- preserve explicit multimodal input capability metadata so later workflow context assembly can gate attachment projection without guessing
- preserve ordered role candidate lists such as `main`, `planner`, and `coder`
- validate every role candidate against known provider and model references

**Step 4: Run the targeted tests**

Run:

```bash
cd core_matrix
bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/integration/provider_catalog_boot_flow_test.rb
```

Expected:

- targeted tests pass

**Step 5: Commit**

```bash
git -C .. add core_matrix/config/providers core_matrix/app/services/provider_catalog core_matrix/test/services core_matrix/test/integration
git -C .. commit -m "feat: add provider catalog config validation"
```

## Stop Point

Stop after provider catalog loading and validation pass their tests.

Do not implement these items in this task:

- provider credential tables
- provider entitlement tables
- provider policy tables

## Completion Record

- status:
  completed on `2026-03-24`
- actual landed scope:
  - added `core_matrix/config/providers/catalog.yml` as the config-backed
    provider and role catalog baseline
  - added `ProviderCatalog::Load` and `ProviderCatalog::Validate`
  - added targeted service and integration tests for catalog loading,
    validation, and boot-time availability
  - added `core_matrix/docs/behavior/provider-catalog-config-and-validation.md`
- plan alignment notes:
  - the task stayed config-backed and did not introduce SQL tables or policy
    rows ahead of Task 05.2
  - ordered role candidates stayed in explicit `provider_handle/model_ref`
    form, matching the role-resolution design
- verification evidence:
  - `cd core_matrix && bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/validate_test.rb test/integration/provider_catalog_boot_flow_test.rb`
    passed with `6 runs, 26 assertions, 0 failures, 0 errors`
- checklist notes:
  - no manual checklist delta was retained for this task because the landed
    behavior is a boot-time config surface already covered by targeted
    automated tests
- retained findings:
  - Rails `config_for` is suitable here because the catalog can live under a
    `shared:` root while still preserving a future path for environment
    overlays if needed
  - multimodal input capability flags stay explicit in config so later
    attachment and context assembly code can gate behavior without provider
    heuristics
  - reference sanity check from
    `references/original/references/openclaw/src/plugins/provider-catalog.ts`:
    explicit provider-qualified identity is worth preserving, but Core Matrix
    intentionally keeps the catalog as static YAML plus boot-time validation
    instead of plugin discovery
- carry-forward notes:
  - Task 05.2 should treat this catalog as the read-side source of provider and
    model identity while adding persisted credentials, entitlements, and
    policies around it
  - later selector-resolution work should preserve ordered role fallback inside
    the selected role only and should not invent implicit cross-role fallback
