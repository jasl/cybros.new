# Core Matrix Task 05.1: Add Provider Catalog Config And Validation

Part of `Core Matrix Kernel Phase 2: Governance And Accounting`.

Use this task document together with:

1. `AGENTS.md`
2. `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-phase-2-governance-and-accounting.md`
5. `docs/design/2026-03-24-core-matrix-model-role-resolution-design.md`

Load this file as the detailed execution unit for Task 05.1. Treat Task 05 and the phase file as ordering indexes, not as the full task body.

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

Do not implement these items in this subtask:

- provider credential tables
- provider entitlement tables
- provider policy tables
