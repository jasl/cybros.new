# Verification Bundle Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop `verification/` from inheriting the full `core_matrix` bundle while making all CoreMatrix-hosted verification code and tests run through an explicit hosted entrypoint.

**Architecture:** Split `verification` into two runtime layers. The default `verification` bundle becomes a small harness-only bundle that loads only bundle-pure adapters, support code, and tests. Rails-backed suites, contracts, and scenario helpers move behind an explicit `verification/hosted/core_matrix` loader and run under the `core_matrix` bundle on purpose instead of via an implicit `BUNDLE_GEMFILE` override.

**Tech Stack:** Ruby, Bundler, Minitest, ActiveSupport, Rails, shell wrappers, monorepo path adapters, `core_matrix`, `core_matrix_cli`.

---

## Boundary Rules

- `verification/Gemfile` exists only to support the harness itself: runners, report builders, artifact tooling, shell/CLI helpers, and pure Ruby tests.
- Scenario assertions must prefer black-box observation first: `cmctl`, app API, logs, exports, generated artifacts, and shell-visible process behavior.
- CoreMatrix-hosted inspection is allowed only when the product does not expose enough observation surface and the scenario must inspect database state, workflow state, mailbox state, or other internal facts.
- Hosted inspection must run through explicit CoreMatrix-owned execution entrypoints such as `bin/rails runner`, hosted helper files, or a dedicated hosted test lane. Do not rely on interactive `rails console`.
- Verification-owned helpers stay under `verification/` even when they run inside the `core_matrix` bundle. Do not move them back into `core_matrix/lib` or `core_matrix/test`.
- Any file that still uses `Acceptance*`, `acceptance`, `manual_acceptance`, or `*_from_core_matrix_*` naming should be treated as cleanup scope during this migration unless there is a documented reason to keep it.

### Task 1: Add a contract for the runtime boundary

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/runtime_boundary_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/runtime_boundary_contract_test.rb`

**Step 1: Write the failing test**

Create a contract test that asserts:
- `/Users/jasl/Workspaces/Ruby/cybros/verification/Gemfile` does not contain `eval_gemfile`
- `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/boot.rb` does not set `BUNDLE_GEMFILE`
- `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper.rb` does not require `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification.rb` does not eagerly load CoreMatrix-hosted suites

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
```

Expected: FAIL because the current runtime boundary is still implicit and CoreMatrix-coupled.

**Step 3: Implement the minimal structure to expose the boundary**

Introduce a minimal pure test helper that can load the contract test without borrowing the CoreMatrix test helper.

**Step 4: Run test to verify it still fails for the intended reasons**

Run the same command again and confirm the failure is now only about the runtime-boundary assertions, not helper boot errors.

**Step 5: Commit**

```bash
git add verification/test/test_helper.rb verification/test/contracts/runtime_boundary_contract_test.rb docs/plans/2026-04-18-verification-bundle-boundary-implementation.md
git commit -m "test: add verification runtime boundary contract"
```

### Task 2: Split `verification` boot into pure and CoreMatrix-hosted loaders

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/boot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/hosted/core_matrix.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/support/governed_validation_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/e2e/manual_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/suites/proof/capstone_review_artifacts.rb`

**Step 1: Write the failing test**

Extend `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/runtime_boundary_contract_test.rb` to require:
- `require "verification"` succeeds under the `verification` bundle without loading Rails
- `require "verification/hosted/core_matrix"` exists as the only supported loader for CoreMatrix-hosted helpers

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
```

Expected: FAIL because `verification` still boots hosted code directly.

**Step 3: Write minimal implementation**

Make these code moves:
- keep `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/boot.rb` bundle-pure only
- define roots, adapters, active suite metadata, CLI support, host validation, conversation runtime validation, and only bundle-pure perf helpers there
- create `/Users/jasl/Workspaces/Ruby/cybros/verification/lib/verification/hosted/core_matrix.rb` that:
  - requires `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/environment`
  - requires hosted helpers such as `governed_validation_support`, `manual_support`, and any proof helpers that rely on CoreMatrix constants
- remove any `ENV["BUNDLE_GEMFILE"]` defaulting from the pure boot path
- remove any direct Rails boot fallback from hosted helpers such as `require Verification::Adapters::CoreMatrix.environment_path unless defined?(Rails.application)`

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add verification/lib/verification.rb verification/lib/verification/boot.rb verification/lib/verification/hosted/core_matrix.rb verification/lib/verification/support/governed_validation_support.rb verification/lib/verification/suites/e2e/manual_support.rb verification/lib/verification/suites/proof/capstone_review_artifacts.rb verification/test/contracts/runtime_boundary_contract_test.rb
git commit -m "refactor: split verification pure and hosted boot paths"
```

### Task 3: Replace the inherited Gemfile with a minimal harness bundle

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/Rakefile`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/test_pure.sh`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/test_core_matrix_hosted.sh`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/test_all.sh`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper_smoke_test.rb`

**Step 1: Write the failing test**

Add expectations to `/Users/jasl/Workspaces/Ruby/cybros/verification/test/test_helper_smoke_test.rb` that:
- `require "verification"` works without the CoreMatrix Gemfile
- pure boot does not define `Rails`
- the shell wrappers exist and point pure tests to the `verification` bundle and hosted tests to the `core_matrix` bundle

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/test_helper_smoke_test.rb
```

Expected: FAIL because the current Gemfile still inherits CoreMatrix.

**Step 3: Write minimal implementation**

Replace the Gemfile with an explicit harness bundle. Start with only gems proven by current source usage:
- `rake`
- `minitest`
- `activesupport`
- `rubyzip`
- `core_matrix_cli`, path: `../core_matrix_cli` only if the pure bundle still needs it

Update `/Users/jasl/Workspaces/Ruby/cybros/verification/Rakefile` so the default task runs only pure tests. Add shell wrappers:
- `verification/bin/test_pure.sh`
- `verification/bin/test_core_matrix_hosted.sh`
- `verification/bin/test_all.sh`

The hosted wrapper should execute from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix` with the CoreMatrix bundle on purpose instead of by hidden override inside Ruby code.

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle install
bundle exec ruby -Itest test/test_helper_smoke_test.rb
bundle exec rake test
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_core_matrix_hosted.sh
```

Expected:
- smoke test PASS
- pure `verification` test suite PASS
- hosted CoreMatrix-backed suite PASS

**Step 5: Commit**

```bash
git add verification/Gemfile verification/Rakefile verification/bin/test_pure.sh verification/bin/test_core_matrix_hosted.sh verification/bin/test_all.sh verification/test/test_helper_smoke_test.rb
git commit -m "refactor: give verification an explicit harness bundle"
```

### Task 4: Split pure tests from CoreMatrix-hosted tests

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/pure_test_helper.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/core_matrix_hosted_test_helper.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/pure/`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/verification/test/core_matrix_hosted/`
- Modify or move:
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/support/cli_support_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/core_matrix_cli_ci_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/repo_licensing_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/profile_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/topology_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/runtime_slot_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/workload_manifest_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/workload_driver_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/metrics_aggregator_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/gate_evaluator_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/capstone_review_artifacts_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/e2e/conversation_runtime_validation_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/active_suite_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/manual_support_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/core_matrix_cli_operator_smoke_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/fresh_start_stack_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/specialist_subagent_export_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/workspace_agent_model_override_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/e2e/manual_support_from_core_matrix_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/perf_workload_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/provider_catalog_override_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/perf/perf_workload_executor_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/capstone_review_artifacts_from_core_matrix_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/fenix_capstone_app_api_roundtrip_contract_test.rb`
  - `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/host_validation_test.rb`

**Step 1: Write the failing test**

Create one smoke test under each helper:
- a pure smoke test that requires `pure_test_helper`
- a hosted smoke test that requires `core_matrix_hosted_test_helper`

The pure smoke test must assert `Rails` is not defined.
The hosted smoke test must assert `Rails.root == Pathname.new("/Users/jasl/Workspaces/Ruby/cybros/core_matrix")`.

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/pure/smoke_test.rb
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_core_matrix_hosted.sh
```

Expected: at least one smoke test fails because the helpers and file layout are not split yet.

**Step 3: Write minimal implementation**

Apply these rules:
- pure tests inherit from `Minitest::Test` unless ActiveSupport is needed only for core extensions
- hosted tests are the only files allowed to require the CoreMatrix test helper
- pure tests move under `verification/test/pure/...`
- hosted tests move under `verification/test/core_matrix_hosted/...`
- contract tests that only inspect files or shell wrappers stay pure even if they previously used `ActiveSupport::TestCase`
- split mixed files instead of moving them wholesale:
  - keep the file-inspection parts of `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/active_suite_contract_test.rb` pure, but move the `GovernedValidationSupport.create_task_context!` assertion into a hosted test file
  - replace `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/manual_support_contract_test.rb` with a pure contract that asserts hosted helpers are not loaded by `verification/boot`, then add a hosted helper smoke test under `verification/test/core_matrix_hosted/...`
  - rename `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/e2e/manual_support_from_core_matrix_test.rb` and `/Users/jasl/Workspaces/Ruby/cybros/verification/test/suites/proof/capstone_review_artifacts_from_core_matrix_test.rb` to explicit hosted names such as `*_core_matrix_hosted_test.rb`
- clean up stale naming while moving files:
  - rename `AcceptanceBenchmarkReportingTest` to `VerificationBenchmarkReportingTest`
  - rename `AcceptanceHostValidationTest` to `VerificationHostValidationTest`
  - remove any remaining `Acceptance*` class names from `verification/test/...`

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec rake test
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_core_matrix_hosted.sh
bash verification/bin/test_all.sh
```

Expected: all pure and hosted test lanes PASS from their intended bundle contexts.

**Step 5: Commit**

```bash
git add verification/test verification/Rakefile verification/bin/test_pure.sh verification/bin/test_core_matrix_hosted.sh verification/bin/test_all.sh
git commit -m "test: split verification pure and core-matrix-hosted suites"
```

### Task 5: Make scenario and helper entrypoints explicit about host ownership

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/scenarios/e2e/*.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/scenarios/perf/*.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/scenarios/proof/*.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/run_active_suite.sh`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/run_with_fresh_start.sh`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/bin/fenix_capstone_app_api_roundtrip_validation.sh`

**Step 1: Write the failing test**

Add assertions to the runtime-boundary contract test that:
- every hosted Ruby scenario requires `verification/hosted/core_matrix`
- no scenario depends on an implicit `BUNDLE_GEMFILE` fallback inside `verification/lib/verification/boot.rb`
- shell entrypoints invoke CoreMatrix-hosted scenarios from an explicit CoreMatrix working directory

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
```

Expected: FAIL because the scenario surface still relies on implicit hosted boot.

**Step 3: Write minimal implementation**

Update every hosted scenario so the required host is visible in code. Prefer one of these two patterns consistently:
- top-level `require "verification/hosted/core_matrix"`
- or shell wrappers that call `bin/rails runner ../verification/scenarios/...` from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`

Do not leave any hidden hosted boot inside the pure loader.

While touching scenarios, clean up stale terminology that contradicts the new surface:
- replace runtime display names such as `"Acceptance Steering Runtime"`, `"Acceptance Human Wait Runtime"`, `"Acceptance Subagent Runtime"`, and `"Acceptance Specialist Export Runtime"` with `Verification` or scenario-specific naming
- keep the existing `VERIFICATION_MODE:` comments, but ensure they describe black-box preference and explain any remaining hosted inspection in plain language

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/run_with_fresh_start.sh verification/scenarios/e2e/fenix_skills_validation.rb
```

Expected: PASS, and the scenario still completes successfully.

**Step 5: Commit**

```bash
git add verification/scenarios verification/bin verification/test/contracts/runtime_boundary_contract_test.rb
git commit -m "refactor: make verification host ownership explicit"
```

### Task 6: Update docs, AGENTS guidance, and CI to match the new boundary

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/verification/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-17-monorepo-verification-rebuild-design.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-17-monorepo-verification-rebuild-implementation.md`

**Step 1: Write the failing test**

Extend `/Users/jasl/Workspaces/Ruby/cybros/verification/test/contracts/runtime_boundary_contract_test.rb` to assert the live docs and CI no longer describe `verification/` as an independent bundle that inherits `core_matrix/Gemfile`.

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
```

Expected: FAIL because the current docs still imply a more independent project shape than the code actually has.

**Step 3: Write minimal implementation**

Update docs to say:
- `verification/` owns the monorepo harness
- pure harness tests run from `/Users/jasl/Workspaces/Ruby/cybros/verification`
- CoreMatrix-hosted verification suites run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`
- `verification/Gemfile` is intentionally minimal and does not inherit the CoreMatrix bundle
- black-box scenario observation is preferred, and CoreMatrix-hosted inspection exists only for DB/internal-state verification that has no equivalent product surface yet

Reword the April 17 rebuild plan docs so they no longer overstate `verification` as a standalone Ruby project. Keep the ownership conclusions, but correct the bundle/runtime wording.

**Step 4: Run test to verify it passes**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec ruby -Itest test/contracts/runtime_boundary_contract_test.rb
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "eval_gemfile|BUNDLE_GEMFILE.*core_matrix/Gemfile|core_matrix/test/test_helper" verification AGENTS.md .github/workflows/ci.yml docs/plans/2026-04-17-monorepo-verification-rebuild-*.md
```

Expected:
- contract test PASS
- `rg` returns no stale live guidance

**Step 5: Commit**

```bash
git add verification/README.md AGENTS.md .github/workflows/ci.yml docs/plans/2026-04-17-monorepo-verification-rebuild-design.md docs/plans/2026-04-17-monorepo-verification-rebuild-implementation.md verification/test/contracts/runtime_boundary_contract_test.rb
git commit -m "docs: align verification guidance with explicit bundle boundaries"
```

### Task 7: Run final verification from both bundle contexts

**Files:**
- Verify only; no intentional source changes

**Step 1: Run the pure harness lane**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros/verification
bundle exec rake test
```

Expected: PASS.

**Step 2: Run the CoreMatrix-hosted verification lane**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_core_matrix_hosted.sh
```

Expected: PASS.

**Step 3: Run one representative scenario**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/run_with_fresh_start.sh verification/scenarios/e2e/fenix_skills_validation.rb
```

Expected: scenario passes and writes artifacts under `/Users/jasl/Workspaces/Ruby/cybros/verification/artifacts/`.

**Step 4: Run the full active suite**

Run:
```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
```

Expected: PASS with no active verification failures.

**Step 5: Commit**

```bash
git add .
git commit -m "chore: verify explicit verification bundle boundaries"
```
