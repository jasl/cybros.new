# 2048 Capstone Acceptance Restoration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the `2048` capstone as an optional-but-formal acceptance proof for the current `CoreMatrix + Fenix + Nexus` stack, and audit the acceptance suite so active scenarios stay orthogonal and purposeful.

**Architecture:** Add optional entrypoint support to `Acceptance::ActiveSuite`, restore the capstone shell wrapper and scenario against the current split runtime topology, then tighten contract coverage so the capstone cannot silently disappear again. Finish with an acceptance-suite audit to keep only scenarios with a clear unique purpose.

**Tech Stack:** Ruby on Rails, shell acceptance harness, ActiveSupport tests, acceptance scenarios, bash wrappers

---

### Task 1: Add optional acceptance entrypoint support

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_active_suite.sh`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/active_suite_contract_test.rb`

**Step 1: Write the failing contract tests**

Add contract coverage that expects:
- an optional entrypoint list API
- a skipped optional entrypoint list API
- the runner to mention skipped optional entrypoints

**Step 2: Run the tests to confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/active_suite_contract_test.rb
```

Expected: failure because optional entrypoint support does not exist yet.

**Step 3: Implement the minimal active-suite optional entrypoint API**

Update `Acceptance::ActiveSuite` to expose:
- default entrypoints
- optional entrypoints
- enabled optional entrypoints
- skipped optional entrypoints

Update `run_active_suite.sh` to print skip lines for disabled optional
entrypoints and still run selected entrypoints exactly once.

**Step 4: Run the tests again**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/active_suite_contract_test.rb
```

Expected: pass.

### Task 2: Restore the capstone shell wrapper and scenario skeleton

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Step 1: Write the failing contract tests**

Add a restored `FenixCapstoneAcceptanceContractTest` that expects:
- the shell wrapper to exist
- the scenario to exist
- `Acceptance::ActiveSuite` to expose the capstone as optional
- the runner and suite to use a dedicated capstone enable flag

**Step 2: Run the test to confirm failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: failure because the files and optional registration do not exist.

**Step 3: Restore the shell wrapper**

Rebuild the historical wrapper so it:
- fresh-starts the stack
- bootstraps the capstone scenario
- activates the runtime worker path
- executes the real provider-backed phase

Do not reintroduce obsolete bundled-runtime assumptions.

**Step 4: Restore the scenario skeleton**

Port only the current, still-relevant parts of the historical scenario:
- artifact setup
- bootstrap and execute phases
- real provider-backed prompt path
- export and review bundle generation

Leave out retired topology code and dead compatibility shims.

**Step 5: Run the contract tests again**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: pass.

### Task 3: Rebind the capstone to the current split runtime topology

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/manual_support.rb`
- Modify as needed: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/*.rb`
- Test: relevant `core_matrix` acceptance helper contract tests

**Step 1: Add failing helper or integration coverage where needed**

Target the smallest contract tests that prove:
- bootstrap emits the credentials the shell wrapper needs
- the scenario can register the current agent/runtime shape
- the scenario does not depend on retired `agent_snapshot` or bundled-runtime
  semantics

**Step 2: Run the targeted tests to confirm failure**

Use the smallest affected test set.

**Step 3: Implement the split-topology adaptation**

Use current helper APIs to:
- create the installation and conversation context
- register the current runtime and agent identity
- execute the provider-backed turn and artifact capture path

Keep the scenario aligned with current `AgentDefinitionVersion` and
`ExecutionRuntimeVersion` semantics.

**Step 4: Run the targeted tests again**

Re-run the affected helper and integration tests until green.

### Task 4: Add capstone suite enablement behavior

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_active_suite.sh`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/acceptance/active_suite_contract_test.rb`

**Step 1: Write or extend failing tests**

Expect:
- the capstone to be listed as optional
- the dedicated env var to control inclusion
- the README to describe both direct invocation and optional suite enablement

**Step 2: Run tests to confirm failure**

Run the minimal contract set again.

**Step 3: Implement optional capstone enablement**

Use one dedicated environment variable, for example:
- `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1`

The direct shell wrapper should not require this flag.

**Step 4: Re-run tests**

Expected: pass.

### Task 5: Audit the active acceptance suite for orthogonality

**Files:**
- Modify as needed: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb`
- Modify as needed: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Modify or delete scenarios only if the audit shows they are obsolete or
  duplicative
- Test: update affected contract tests

**Step 1: Inventory every active scenario and wrapper**

For each entrypoint, record:
- primary purpose
- unique contract
- overlap with other scenarios
- whether it is smoke, edge, pressure, or capstone proof

**Step 2: Decide whether to keep, move, or remove**

Only remove an entrypoint when:
- its topology assumptions are obsolete, or
- another entrypoint already covers the same behavior at the same or higher
  confidence, or
- it no longer proves a meaningful contract

**Step 3: Apply cleanup or supplementation**

If gaps appear, add the lightest scenario needed to cover the missing contract.
If duplication appears, remove or archive the weaker entrypoint.

**Step 4: Re-run the active-suite contract tests**

Ensure every live entrypoint still exists and the runner behavior is consistent.

### Task 6: Run targeted capstone verification

**Files:**
- No code changes expected unless failures reveal bugs

**Step 1: Run the capstone contract and helper tests**

Run the exact tests affected by this work.

**Step 2: Run the capstone scenario directly if prerequisites are available**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

If provider prerequisites are unavailable, document that clearly and stop before
claiming full proof.

**Step 3: Run the active suite with the optional capstone enabled**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Expected: the capstone appears as a selected entrypoint instead of a skipped
optional entrypoint.

### Task 7: Run full verification

**Files:**
- No code changes expected unless failures reveal regressions

**Step 1: Run project verification in the repo-prescribed order**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bun run lint:js
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference
bundle exec rake
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
docker build -f images/nexus/Dockerfile -t nexus-local .
docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh
```

**Step 2: Run the active acceptance suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/run_active_suite.sh
```

**Step 3: Run the final capstone proof**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

**Step 4: Commit**

Use one or more focused commits that separate:
- suite infrastructure changes
- capstone restoration
- audit cleanup if it grows large enough

---

Plan complete and saved to `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-12-acceptance-capstone-restoration.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
