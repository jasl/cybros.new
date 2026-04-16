# CoreMatrix CLI Acceptance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an isolated CLI operator smoke lane and switch the 2048 capstone setup phase to `cmctl`, while keeping the current final-proof acceptance path unchanged.

**Architecture:** Add automation-safe environment overrides to `core_matrix_cli`, add an acceptance-owned CLI runner under `acceptance/lib`, wire a standalone CLI smoke scenario into the active suite, then migrate only the capstone setup phase to the CLI runner and keep the final conversation/runtime proof on the existing harness.

**Tech Stack:** Ruby, Thor, Minitest, Rails runner acceptance scenarios, shell process orchestration, existing acceptance artifact/review helpers.

---

### Task 1: Add automation-safe CLI environment overrides

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/config_store.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_store.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/browser_launcher.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/config_store_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/credential_store_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`

**Steps:**
1. Write failing tests for env-driven config path override, forced file credential store, credential path override, and browser-disable behavior.
2. Run the focused CLI tests and watch them fail.
3. Implement the minimal env override logic.
4. Re-run the focused CLI tests and make them pass.

### Task 2: Add acceptance-owned `cmctl` runner support

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/cli_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/boot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/cli_support_test.rb`

**Steps:**
1. Write failing tests for a helper that runs `cmctl` with isolated config/credential paths and captures stdout/stderr/exit status.
2. Run the focused tests and verify they fail for the missing helper.
3. Implement a small helper surface:
   - run command with scripted stdin
   - set automation env vars
   - read back config/credential JSON
   - write evidence files under an artifact directory
4. Re-run the focused tests and make them pass.

### Task 3: Add standalone CLI operator smoke acceptance

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/core_matrix_cli_operator_smoke_contract_test.rb`

**Steps:**
1. Write a failing contract test that asserts the new acceptance entrypoint exists and produces the expected artifact/evidence structure.
2. Run the focused test and verify it fails.
3. Implement the smoke scenario to exercise:
   - `cmctl init`
   - `cmctl status`
   - `cmctl workspace create`
   - `cmctl workspace use`
   - `cmctl agent attach`
4. Add the scenario to the active suite and README.
5. Re-run the focused test and the new scenario until they pass.

### Task 4: Switch capstone setup phase to CLI

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/capstone_review_artifacts.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Steps:**
1. Write a failing capstone contract test that expects CLI evidence files and CLI-derived setup state in the artifact bundle.
2. Run the focused capstone contract test and verify it fails.
3. Update the capstone scenario so that:
   - initial installation bootstrap/login goes through `cmctl`
   - bundled-runtime registration still uses the existing acceptance helper
   - setup state refresh is re-read through `cmctl`
   - session/config values are read back from CLI automation storage
   - final conversation/app-api proof remains unchanged
4. Update review artifact generation to mention CLI setup evidence.
5. Re-run the focused capstone contract test and direct capstone scenario until they pass.

### Task 5: Full verification

**Files:**
- No new files expected

**Steps:**
1. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
   bundle exec rake test
   ```
2. Run:
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
3. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros
   ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
   ```
4. Inspect the latest CLI smoke artifact and capstone artifact, including CLI evidence and the final capstone database/export state.

Plan complete and saved to the two files above. Two execution options:

1. 这个会话里直接执行
2. 单独会话并行执行
