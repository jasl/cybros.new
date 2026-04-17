# Monorepo Verification Rebuild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the live `acceptance` surface with a first-class `verification` project, move harness-owned code/tests out of product projects, and delete obsolete compatibility paths in one direct migration.

**Architecture:** Build a new top-level `verification/` project, migrate the current live harness into it, introduce explicit product adapters, keep product-owned e2e inside each product project, and remove all old `acceptance` references from the live developer surface. The migration is intentionally destructive: there are no compatibility wrappers, alias constants, forwarding files, or legacy runner shims. `verification/` owns a small harness bundle plus explicit CoreMatrix-hosted lanes instead of inheriting the full `core_matrix` bundle by default.

**Tech Stack:** Ruby, Minitest, Rails runner scenarios, shell wrappers, GitHub Actions, monorepo path adapters, existing `core_matrix`, `core_matrix_cli`, `agents/fenix`, and `images/nexus` developer surfaces.

---

### Task 1: Scaffold the new `verification/` project shell

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/README.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/Gemfile`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/Rakefile`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/boot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper.rb`

**Steps:**
1. Write a failing smoke test in `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper_smoke_test.rb` that requires `verification/boot` and asserts `Verification` is defined.
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/verification
   bundle exec ruby -Itest test/test_helper_smoke_test.rb
   ```
   Expected: fail because the `verification` project shell does not exist yet.
3. Create the minimal `verification/` project files and namespace so the smoke test can load.
4. Re-run the smoke test and make it pass.
5. Commit:
   ```bash
   git add verification docs/plans/2026-04-17-monorepo-verification-rebuild-design.md docs/plans/2026-04-17-monorepo-verification-rebuild-implementation.md
   git commit -m "refactor: scaffold monorepo verification project"
   ```

### Task 2: Move the live harness from `acceptance/` into `verification/`

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/*`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/scenarios/*`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/artifacts/`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/logs/`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/active_suite.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/support/*`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/e2e/*`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/perf/*`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/proof/*`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/*`

**Steps:**
1. Write a failing contract test in `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/active_suite_contract_test.rb` that asserts the new `verification/bin/run_active_suite.sh` exists and loads `verification/lib/verification/active_suite`.
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/verification
   bundle exec ruby -Itest test/contracts/active_suite_contract_test.rb
   ```
   Expected: fail because the files still live under `acceptance/`.
3. Move the live harness files into `verification/`, create the new `artifacts/`
   and `logs/` roots there, and rename the namespace from `Acceptance` to
   `Verification`.
4. Re-run the focused contract test until it passes.
5. Scan for stale namespace/path references:
   ```bash
   rg -n 'acceptance/|module Acceptance|Acceptance::' /Users/jasl/Workspaces/Ruby/cybros/verification
   ```
   Expected: only intentional historical strings in comments or fixture text remain.
6. Commit:
   ```bash
   git add verification
   git commit -m "refactor: move acceptance harness into verification"
   ```

### Task 3: Introduce explicit product adapters

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/adapters/core_matrix.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/adapters/core_matrix_cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/adapters/fenix.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/adapters/nexus.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/boot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/adapters/core_matrix_adapter_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/adapters/core_matrix_cli_adapter_test.rb`

**Steps:**
1. Write failing adapter tests that assert each adapter resolves the expected fixed monorepo path and emits a clear error when the path is missing.
2. Run the focused adapter tests and verify they fail.
3. Implement minimal adapters for path discovery, command construction, and environment assembly.
4. Replace direct path math in moved harness code with adapter calls.
5. Re-run the adapter tests and the active suite contract test until they pass.
6. Commit:
   ```bash
   git add verification
   git commit -m "refactor: add monorepo verification adapters"
   ```

### Task 4: Move repo-root verification assets into `verification/`

**Files:**
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/Rakefile`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/capstone_review_artifacts_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/gate_evaluator_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/metrics_aggregator_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/profile_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/runtime_slot_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/topology_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/workload_driver_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/acceptance/perf/workload_manifest_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/capstone_review_artifacts_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/gate_evaluator_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/metrics_aggregator_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/profile_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/runtime_slot_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/topology_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/workload_driver_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/workload_manifest_test.rb`

**Steps:**
1. Write a failing `verification/Rakefile` smoke test that runs `bundle exec rake test` inside `verification/` and expects the moved suite paths.
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/verification
   bundle exec rake test
   ```
   Expected: fail because repo-root tests still own the suite.
3. Move the repo-root `Rakefile` and `test/acceptance/*` content into `verification/test/suites/*`.
4. Update any require paths and namespace references needed for the new location.
5. Re-run `bundle exec rake test` in `verification/` until the moved suite passes.
6. Commit:
   ```bash
   git add verification
   git commit -m "refactor: move root verification tests into verification"
   ```

### Task 5: Move harness helpers and harness tests out of `core_matrix`

**Files:**
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/lib/manual_acceptance/conversation_runtime_validation.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/manual_acceptance/conversation_runtime_validation_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/active_suite_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/benchmark_reporting_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/capstone_review_artifacts_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/cli_support_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/core_matrix_cli_operator_smoke_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/host_validation_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/manual_support_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_provider_catalog_override_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/perf_workload_executor_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fresh_start_stack_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/specialist_subagent_export_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/workspace_agent_model_override_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/e2e/conversation_runtime_validation_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/e2e/manual_support_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/benchmark_reporting_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/active_suite_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/core_matrix_cli_operator_smoke_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/fresh_start_stack_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/fenix_capstone_app_api_roundtrip_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/specialist_subagent_export_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/workspace_agent_model_override_contract_test.rb`

**Steps:**
1. Write failing tests in `verification/test/*` for the moved harness behavior before deleting the old `core_matrix` copies.
2. Run the focused `verification` tests and verify they fail because the code still lives under `core_matrix`.
3. Move the helper implementations and test logic into `verification/`.
4. Delete the old `core_matrix` harness code/tests once the new `verification` tests pass.
5. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/e2e/protocol
   ```
   Expected: CoreMatrix product-owned e2e still pass after the harness cleanup.
6. Commit:
   ```bash
   git add verification core_matrix
   git commit -m "refactor: remove verification harness leaks from core matrix"
   ```

### Task 6: Rewrite live CI and developer instructions

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.gitignore`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/images/nexus/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/design/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/reports/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/README.md`

**Steps:**
1. Write a failing doc/CI contract test in `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/live_reference_contract_test.rb` that scans live docs and workflow files for stale `acceptance/` paths.
2. Run the contract test and verify it fails against the current repo.
3. Update CI commands, AGENTS instructions, and live docs to point to `verification/...`.
4. Re-run the live-reference contract test until it passes.
5. Spot-check:
   ```bash
   rg -n 'acceptance/' /Users/jasl/Workspaces/Ruby/cybros/.github /Users/jasl/Workspaces/Ruby/cybros/AGENTS.md /Users/jasl/Workspaces/Ruby/cybros/core_matrix/README.md /Users/jasl/Workspaces/Ruby/cybros/images/nexus/README.md /Users/jasl/Workspaces/Ruby/cybros/docs/README.md /Users/jasl/Workspaces/Ruby/cybros/docs/checklists/README.md /Users/jasl/Workspaces/Ruby/cybros/docs/design /Users/jasl/Workspaces/Ruby/cybros/docs/plans/README.md /Users/jasl/Workspaces/Ruby/cybros/docs/reports/README.md /Users/jasl/Workspaces/Ruby/cybros/verification
   ```
   Expected: no live-path references remain outside archived history or the
   intentionally historical rebuild plan files.
6. Commit:
   ```bash
   git add .github .gitignore AGENTS.md core_matrix/README.md images/nexus/README.md docs verification
   git commit -m "docs: repoint live guidance to verification"
   ```

### Task 7: Migrate existing harness-owned acceptance test files into `verification`

**Files:**
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/cli_support_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/core_matrix_cli_ci_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/repo_licensing_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/support/cli_support_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/core_matrix_cli_ci_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/repo_licensing_contract_test.rb`

**Steps:**
1. Write the target `verification` tests first, preserving only one CLI support test copy and deleting duplicate coverage after the new suite is green.
2. Run the focused `verification` test files and confirm they fail before the move.
3. Move the `acceptance/test/*` files into `verification/test/*`, adjust require paths and namespaces, and delete the old copies.
4. Re-run the focused `verification` tests until they pass.
5. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/verification
   bundle exec rake test
   ```
   Expected: the moved harness-owned tests run only from `verification`.
6. Commit:
   ```bash
   git add verification
   git commit -m "test: consolidate harness-owned tests under verification"
   ```

### Task 8: Delete obsolete compatibility paths and dead code

**Files:**
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/acceptance`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test`
- Delete any remaining forwarding files or alias constants that preserve old `acceptance` ownership

**Steps:**
1. Write a failing cleanup contract test in `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/no_acceptance_surface_test.rb` that asserts:
   - `/Users/jasl/Workspaces/Ruby/cybros/acceptance` does not exist
   - repo-root `Rakefile` does not exist
   - no live `module Acceptance` or `Acceptance::` constants remain
2. Run the cleanup contract test and verify it fails before deletion.
3. Delete the old directory/files and remove stale namespace usage.
4. Re-run the cleanup contract test until it passes.
5. Run:
   ```bash
   rg -n 'module Acceptance|Acceptance::|manual_acceptance|acceptance/' /Users/jasl/Workspaces/Ruby/cybros --glob '!docs/archived*/**' --glob '!docs/plans/2026-04-17-monorepo-verification-rebuild-*.md'
   ```
   Expected: no live compatibility leftovers remain.
6. Commit:
   ```bash
   git add -A
   git commit -m "refactor: delete legacy acceptance surface"
   ```

### Task 9: Run full verification and inspect the rebuilt surface

**Files:**
- No new files expected

**Steps:**
1. Run the rebuilt verification test suite:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/verification
   bundle exec rake test
   ```
2. Run the product suites that should still hold after the migration:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/brakeman --no-pager
   bin/bundler-audit
   bin/rubocop -f github
   bun run lint:js
   bin/rails db:test:prepare
   bin/rails test
   bin/rails test:system
   ```
3. Run the monorepo verification gate:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros
   ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
   ```
4. Inspect the newest `verification/artifacts/*` bundle and confirm:
   - active suite summary references `verification`
   - review output is understandable without `acceptance` terminology
   - proof/perf/e2e evidence landed in the expected directories
5. Run the final stale-reference sweep:
   ```bash
   rg -n 'acceptance/|module Acceptance|Acceptance::|manual_acceptance|ACTIVE_ACCEPTANCE|ACCEPTANCE_' /Users/jasl/Workspaces/Ruby/cybros --glob '!docs/archived*/**' --glob '!docs/plans/2026-04-17-monorepo-verification-rebuild-*.md'
   ```
   Expected: no live matches remain outside the intentionally historical rebuild
   plan files.
6. Commit:
   ```bash
   git add -A
   git commit -m "refactor: finish monorepo verification rebuild"
   ```

Plan complete and saved to `docs/plans/2026-04-17-monorepo-verification-rebuild-implementation.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, and execute the migration here.
2. Parallel Session (separate) - Open a new session and execute the plan task-by-task with `executing-plans`.

Which approach?
