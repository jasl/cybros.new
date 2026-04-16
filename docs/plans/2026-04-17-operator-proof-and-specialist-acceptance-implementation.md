# Operator Proof And Specialist Acceptance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the remaining proof gaps for operator CLI auth/provider setup,
mounted model-selector overrides, and specialist/subagent export visibility.

**Architecture:** Keep CLI improvements in `core_matrix_cli`, acceptance helpers
in `acceptance/lib`, and selector/export proof logic in acceptance scenarios.
Do not move agent-owned prompt or profile business logic into CoreMatrix.

**Tech Stack:** Ruby, Thor, Rails runner acceptance scenarios, Minitest,
existing acceptance artifact/export helpers.

---

### Task 1: Extend CLI smoke and status semantics

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/status_command_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/cli_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/core_matrix_cli_operator_smoke_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`

**Steps:**
1. Write failing CLI tests for `status` showing both installation defaults and
   selected local workspace / workspace-agent context.
2. Write a failing acceptance contract asserting the smoke scenario now covers
   `cmctl auth login` and `cmctl providers codex login`.
3. Add any small helper support needed for scripted CLI auth/provider evidence.
4. Implement the runtime/status output changes and update the smoke scenario.
5. Re-run focused CLI and acceptance contract tests until they pass.

### Task 2: Add mounted model-selector override acceptance

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/manual_support.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/workspace_agent_model_override_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/workspace_agent_model_override_contract_test.rb`

**Steps:**
1. Add failing contract coverage for a new acceptance scenario that proves a
   mounted interactive model override through app-api.
2. Add any missing acceptance helper support, such as `PATCH` JSON requests.
3. Implement the scenario using the deterministic `role:mock` provider path.
4. Assert the observed provider/model came from the mount override with no
   explicit selector on the conversation create request.
5. Re-run focused tests until they pass.

### Task 3: Add specialist/subagent export proof acceptance

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/specialist_subagent_export_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/specialist_subagent_export_contract_test.rb`

**Steps:**
1. Write a failing contract test asserting the new scenario exists and proves
   delegation summary / debug export / workflow-mermaid coverage.
2. Implement the scenario with a mount configured to allow only the `tester`
   specialist and instructions that explicitly require delegating the
   verification step to that specialist.
3. If the first provider-backed path is unstable, use the smallest possible
   deterministic acceptance-owned control hook without widening the product
   boundary further.
4. Assert export/debug-export/review artifacts contain specialist information.
5. Re-run focused tests until they pass.

### Task 4: Full verification and audit

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
4. Inspect:
   - the latest CLI smoke artifact
   - the new model-override acceptance artifact
   - the new specialist/subagent acceptance artifact
   - the latest capstone artifact and database state

Plan complete and saved to the two files above. Two execution options:

1. 这个会话里直接执行
2. 单独会话并行执行
