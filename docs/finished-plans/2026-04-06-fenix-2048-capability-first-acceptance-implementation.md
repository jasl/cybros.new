# Fenix 2048 Capability-First Acceptance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the existing 2048 capstone so it scores capability activation and failure classification, not only workload completion.

**Architecture:** Keep the current 2048 acceptance scenario as the mother benchmark and add two shared acceptance helpers: one for capability probes and one for failure classification. The scenario will emit `capability-activation.json` and `failure-classification.json`, then fold their summaries into the existing `run-summary.json`.

**Tech Stack:** Ruby, Rails runner acceptance scripts, Active Record, JSON artifacts, Minitest contract tests

---

### Task 1: Add contract tests for the new benchmark artifacts

**Files:**
- Modify: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Step 1: Add a failing contract test for capability activation output**

Add a test that reads `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
and asserts it writes `artifact_dir.join("capability-activation.json")`.

**Step 2: Add a failing contract test for failure classification output**

Add a second test asserting the scenario writes
`artifact_dir.join("failure-classification.json")`.

**Step 3: Add a failing contract test for helper usage**

Assert the scenario references helper entrypoints such as:

- `Acceptance::CapabilityActivation`
- `Acceptance::FailureClassification`

**Step 4: Run the contract test file and verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: FAIL because the new artifact writes and helper references do not yet
exist.

**Step 5: Commit**

```bash
git add core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb
git commit -m "test: require capability-first 2048 benchmark artifacts"
```

### Task 2: Add a shared capability activation helper

**Files:**
- Create: `acceptance/lib/capability_activation.rb`
- Modify: `acceptance/lib/boot.rb`

**Step 1: Define the scenario contract structure**

Implement a small helper API that can accept data like:

```ruby
{
  "scenario" => "fenix_2048_capstone",
  "capabilities" => [
    { "key" => "workspace_editing", "required" => true },
    { "key" => "command_execution", "required" => true }
  ]
}
```

**Step 2: Implement evidence collectors**

Add helper methods that can build evidence entries from:

- `ToolInvocation`
- `CommandRun`
- `SubagentConnection`
- exported artifact presence
- workspace file presence
- supervision artifact presence

**Step 3: Implement the report shape**

Return a payload with:

- `scenario`
- `required_capabilities`
- `summary`

Each capability row should include:

- `key`
- `required`
- `activated`
- `evidence_level`
- `db_evidence`
- `artifact_evidence`
- `notes`

**Step 4: Export the helper through the acceptance boot path**

Require the helper from `acceptance/lib/boot.rb` so scenarios can use it.

**Step 5: Add a tiny unit-like smoke script comment example**

Document usage inside the helper file so future scenarios can follow the same
shape without re-inventing probes.

**Step 6: Commit**

```bash
git add acceptance/lib/capability_activation.rb acceptance/lib/boot.rb
git commit -m "feat: add shared acceptance capability activation helper"
```

### Task 3: Add a shared failure classification helper

**Files:**
- Create: `acceptance/lib/failure_classification.rb`
- Modify: `acceptance/lib/boot.rb`

**Step 1: Define classification categories**

Support these primary categories:

- `model_variance`
- `environment_defect`
- `agent_design_gap`
- `kernel_gap`
- `harness_gap`
- `user_input_gap`
- `unknown`

**Step 2: Define outcome states**

Support:

- `pass_clean`
- `pass_recovered`
- `pass_diagnostic`
- `fail_model`
- `fail_system`
- `fail_harness`

**Step 3: Implement a rule-based classifier**

The helper should accept:

- capability activation summary
- workload outcome
- diagnostics
- rescue history
- optional notes

Then derive:

- `outcome`
- `workload_outcome`
- `system_behavior_outcome`
- `classification`
- `timeline`
- `recommended_actions`

**Step 4: Encode the npm/image-style environment failure path**

Add explicit rules so repeated build/test/toolchain failures with otherwise
healthy loop behavior classify as `environment_defect`, not generic agent
failure.

**Step 5: Export the helper through the acceptance boot path**

Require it from `acceptance/lib/boot.rb`.

**Step 6: Commit**

```bash
git add acceptance/lib/failure_classification.rb acceptance/lib/boot.rb
git commit -m "feat: add shared acceptance failure classification helper"
```

### Task 4: Thread capability probes into the 2048 capstone

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`

**Step 1: Define the 2048 capability contract in the scenario**

Add a local constant for required capabilities:

- `workspace_editing`
- `command_execution`
- `browser_verification`
- `supervision`
- `export_roundtrip`

And optional capabilities:

- `skills`
- `subagents`

**Step 2: Collect the evidence inputs already produced by the scenario**

Reuse existing local data instead of re-querying blindly:

- command run exports
- host validation artifacts
- supervision trace
- export/debug export results
- diagnostics
- subagent connections
- workspace artifact checks

**Step 3: Build the capability activation report**

Generate the report and write:

```ruby
write_json(artifact_dir.join("capability-activation.json"), capability_report)
```

**Step 4: Add the capability report path into `run-summary.json`**

Include:

- path to `capability-activation.json`
- required capability pass counts
- optional capability activation counts

**Step 5: Run the contract test to verify it now passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: PASS for the new artifact references.

**Step 6: Commit**

```bash
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb
git commit -m "feat: add capability activation reporting to 2048 capstone"
```

### Task 5: Thread failure classification into the 2048 capstone

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`

**Step 1: Define the workload outcome explicitly**

Derive one of:

- `complete`
- `partial`
- `blocked`
- `failed`

Use existing summary inputs such as:

- host/browser verification
- transcript/export completion
- final conversation state

**Step 2: Add rescue history capture**

Use existing attempt or collaboration notes paths where possible. If the current
scenario does not encode enough structure, add a small explicit rescue history
array local to the scenario and populate it when the scenario injects operator
help or retry direction.

**Step 3: Build the failure classification report**

Generate the report and write:

```ruby
write_json(artifact_dir.join("failure-classification.json"), failure_report)
```

**Step 4: Fold the classification summary into `run-summary.json`**

Add:

- `benchmark_outcome`
- `workload_outcome`
- `system_behavior_outcome`
- `failure_primary_category`
- `failure_recommended_actions`

**Step 5: Keep the workload summary separate from system behavior summary**

Do not collapse them into one boolean.

**Step 6: Commit**

```bash
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb
git commit -m "feat: classify 2048 capstone failures by capability evidence"
```

### Task 6: Add benchmark markdown summaries for humans

**Files:**
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`

**Step 1: Add a capability summary markdown artifact**

Write `capability-activation.md` with:

- required capabilities
- activation result
- key evidence refs

**Step 2: Add a failure summary markdown artifact**

Write `failure-classification.md` with:

- workload outcome
- system behavior outcome
- primary classification
- supporting timeline
- recommended actions

**Step 3: Reference both markdown artifacts from `workspace-artifacts.md` or `run-summary.json`**

This keeps the benchmark inspectable without opening JSON first.

**Step 4: Commit**

```bash
git add acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb
git commit -m "docs: add human-readable capability and failure benchmark artifacts"
```

### Task 7: Re-run the 2048 capstone and inspect the new benchmark outputs

**Files:**
- No code changes by default

**Step 1: Run acceptance contract tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb test/lib/fresh_start_stack_contract_test.rb
```

Expected: PASS

**Step 2: Run the 2048 capstone**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

Expected:

- a new timestamped artifact directory
- `capability-activation.json`
- `failure-classification.json`
- updated `run-summary.json`

**Step 3: Inspect the outputs**

Inspect:

- latest `acceptance/artifacts/*2048*/capability-activation.json`
- latest `acceptance/artifacts/*2048*/failure-classification.json`
- latest `acceptance/artifacts/*2048*/run-summary.json`
- latest `acceptance/artifacts/*2048*/workspace-validation.md`
- latest `acceptance/artifacts/*2048*/supervision-status.md`

Confirm:

- required capabilities are evaluated from evidence, not self-report
- optional capabilities do not incorrectly fail the scenario
- environment/toolchain issues can classify as `environment_defect`

**Step 4: Run project verification after the acceptance changes stabilize**

For `core_matrix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

For `agents/fenix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

**Step 5: Commit**

```bash
git add acceptance core_matrix/test/lib
git commit -m "test: upgrade 2048 capstone into capability-first benchmark"
```
