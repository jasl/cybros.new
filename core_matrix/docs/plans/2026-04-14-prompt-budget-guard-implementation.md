# Prompt Budget Guard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add authoritative prompt-budget protection for `core_matrix`
provider turns so oversized requests are compacted or rejected predictably,
workspace policy can control prompt-compaction behavior, and provider overflow
surfaces as a user-recoverable prompt-size failure instead of
`internal_unexpected_error`.

**Architecture:** `ProviderExecution::ExecuteRoundLoop` will call a new
`PromptBudgetGuard` after the final provider message list is assembled and
before dispatch. The guard will consume a frozen prompt-compaction policy
resolved from workspace config over agent defaults, estimate tokens with a
deterministic fallback chain, explicitly orchestrate runtime-first compaction
with an embedded fallback, and emit structured overflow failures and
remediation metadata when the request still cannot fit.

**Tech Stack:** Ruby on Rails, Active Record, Minitest, `tiktoken_ruby`,
`tokenizers`, `SimpleInference`, embedded agents, Fenix canonical config,
workspace policy API.

---

### Task 1: Lock Prompt-Budget Contracts Before Wiring New Surfaces

**Files:**
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Create: `core_matrix/test/services/provider_execution/token_estimator_test.rb`

**Step 1: Write failing `TokenEstimator` tests**

Create `token_estimator_test.rb` with cases that expect:

- exact local tokenizer path wins when an asset is available
- `tiktoken` fallback is used when no exact tokenizer asset exists
- heuristic fallback is used when neither tokenizer path is available
- heuristic fallback intentionally over-estimates instead of under-estimating

**Step 2: Write failing `PromptBudgetGuard` tests**

Create `prompt_budget_guard_test.rb` with cases for:

- `allow` when the final message list is below the soft threshold
- `compact` when the final message list crosses the soft threshold
- `reject` when the newest selected user input alone exceeds the remaining hard
  budget
- retry metadata for `current_message` vs `full_context`

Stub compaction so these tests fail on missing guard logic, not on unrelated
runtime plumbing.

**Step 3: Write failing overflow-classification tests**

Extend `failure_classification_test.rb` so it expects:

- HTTP `413` to map to `prompt_too_large_for_retry` or
  `context_window_exceeded_after_compaction`
- HTTP `400` / `422` bodies containing `prompt too long`, `context length`,
  `maximum context length`, or `request too large` to map to explicit
  prompt-size failures
- these failures to use manual retry instead of terminal implementation error

**Step 4: Write failing failure-persistence tests**

Extend `execute_turn_step_test.rb` so it expects persisted failure payloads to
include:

- `retry_mode`
- `editable_tail_input`
- `failure_scope`
- `turn_id`
- `selected_input_message_id`

**Step 5: Run the targeted tests and verify they fail for the right reasons**

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: failures showing the new estimator/guard classes do not exist yet and
overflow is still classified generically with no structured remediation
metadata.

**Step 6: Commit**

```bash
git add \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
git commit -m "test: lock prompt budget guard contracts"
```

### Task 2: Add Prompt-Compaction Defaults And Workspace Policy Storage

**Files:**
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Create: `core_matrix/db/migrate/<timestamp>_add_config_to_workspaces.rb`
- Modify: `core_matrix/db/schema.rb`
- Modify: `core_matrix/app/models/workspace.rb`
- Modify: `core_matrix/app/services/workspace_policies/upsert.rb`
- Modify: `core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb`
- Modify: `core_matrix/app/controllers/app_api/workspaces/policies_controller.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Modify: `core_matrix/test/requests/app_api/workspace_policies_test.rb`
- Modify: `core_matrix/test/models/workspace_test.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/test_helper.rb`

**Step 1: Write failing config-surface tests**

Extend Fenix manifest tests so they expect canonical config to include:

- `features.prompt_compaction.enabled`
- `features.prompt_compaction.mode`

Extend workspace policy request/model tests so they expect:

- `workspace_policy.features.prompt_compaction.enabled`
- `workspace_policy.features.prompt_compaction.mode`
- invalid prompt-compaction values to be rejected

Also extend bundled runtime registration tests so the packaged definition/config
shape round-trips with prompt-compaction defaults.

**Step 2: Add Fenix canonical config defaults**

Update the Fenix canonical config files so they define:

- `features.prompt_compaction.enabled`
- `features.prompt_compaction.mode`

Keep the default aligned with the design:

- enabled
- `runtime_first`

Verify the manifest integration test is the primary Fenix assertion point. Do
not add unnecessary `BuildRoundInstructions` work in this task.

**Step 3: Add structured workspace config storage and policy plumbing**

Add a JSONB `config` column to `workspaces` with a hash default.

Update:

- `Workspace` validations so `config` is always a hash
- `WorkspacePolicies::Upsert` to accept and validate nested
  `features.prompt_compaction`
- `WorkspacePolicyPresenter` to project prompt-compaction policy
- `AppAPI::Workspaces::PoliciesController` to accept prompt-compaction updates

Keep the prompt-compaction shape structured for future expansion instead of
flattening fields onto the workspace row.

**Step 4: Update bundled/runtime and test helper defaults**

Update bundled runtime registration defaults and test helpers so new agent
definitions, bundled manifests, and shared fixtures all carry the prompt
compaction config shape consistently.

This task is complete only when there is no hidden fallback to `{}` in the
common registration/test setup path for prompt-compaction defaults.

**Step 5: Run the targeted tests and verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:migrate
bin/rails db:test:prepare
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb
```

Expected: Fenix manifest exposes prompt-compaction defaults, workspace policy
show/update persists structured prompt-compaction config, and bundled runtime
fixtures round-trip the new shape.

**Step 6: Commit**

```bash
git add \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.schema.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/config/canonical_config.defaults.json \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_manifest_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate/*_add_config_to_workspaces.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workspace.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workspace_policies/upsert.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/workspace_policy_presenter.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces/policies_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/installations/register_bundled_agent_runtime.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspace_policies_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workspace_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb
git commit -m "feat: add workspace prompt compaction policy"
```

### Task 3: Freeze Effective Prompt-Compaction Policy Into The Execution Snapshot

**Files:**
- Create: `core_matrix/app/services/provider_execution/prompt_compaction_policy.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Step 1: Write failing policy-resolution tests**

Extend `build_execution_snapshot_test.rb` so it expects prompt-compaction policy
resolution precedence to be:

- workspace override
- agent canonical config default
- compatibility fallback for older runtimes missing prompt-compaction config

Also assert that the resolved policy is frozen into the execution snapshot
payload consumed by provider execution.

**Step 2: Implement effective policy resolution**

Add a small service such as `ProviderExecution::PromptCompactionPolicy` that:

- accepts workspace config
- accepts agent default canonical config
- returns a normalized effective policy

Use named constants for fallback defaults and reject invalid mode values early.

**Step 3: Freeze the policy during snapshot build**

Update `BuildExecutionSnapshot` so `provider_context` includes the resolved
prompt-compaction policy for the turn under
`provider_context.feature_policies.prompt_compaction`. The round loop should
later consume this frozen value, not query `workspace` live.

**Step 4: Run the targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/workflows/build_execution_snapshot_test.rb
```

Expected: the execution snapshot now carries a stable, resolved
prompt-compaction policy.

**Step 5: Commit**

```bash
git add \
  app/services/provider_execution/prompt_compaction_policy.rb \
  app/services/workflows/build_execution_snapshot.rb \
  test/services/workflows/build_execution_snapshot_test.rb
git commit -m "feat: freeze prompt compaction policy in snapshots"
```

### Task 4: Implement Token Estimation And Guard Decisions

**Files:**
- Create: `core_matrix/app/services/provider_execution/token_estimator.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Write failing round-loop guard tests for non-compaction outcomes**

Extend `execute_round_loop_test.rb` with cases that expect:

- dispatch proceeds when the guard returns `allow`
- dispatch is blocked with a typed local error when the guard returns `reject`

Do not add compaction-orchestration expectations yet. Those belong to Task 5.

**Step 2: Implement `TokenEstimator` minimally to satisfy the tests**

Add `TokenEstimator` with an API that accepts:

- message list
- `tokenizer_hint`
- hard budget context

Implement the fallback chain in order:

- exact local tokenizer
- `tiktoken`
- heuristic estimate

Return both the estimated token count and the estimator strategy used.

**Step 3: Implement `PromptBudgetGuard` decision logic**

Add `PromptBudgetGuard` with named constants for:

- soft-budget reserve behavior
- heuristic safety behavior
- max compaction attempts
- max overflow recovery attempts

The guard should expose a result object or hash that includes:

- `decision`
- `estimated_tokens`
- `estimator_strategy`
- `failure_scope`
- `retry_mode`

For this task, a `compact` decision only blocks direct dispatch. The actual
compaction orchestration is added in Task 5.

**Step 4: Wire the guard into `ExecuteRoundLoop` before dispatch**

Update `ExecuteRoundLoop` so it:

- assembles final provider messages
- calls `PromptBudgetGuard`
- dispatches only when the guard returns `allow`
- raises a typed local error when the guard returns `reject`
- raises a separate typed local error for `compact` until Task 5 implements the
  orchestration path

This keeps the test boundary explicit and avoids hiding red tests across tasks.

**Step 5: Run the targeted test set and make it green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Expected: estimator and guard tests pass, and round-loop dispatch is now gated
for `allow` vs `reject` without compaction orchestration yet.

**Step 6: Commit**

```bash
git add \
  app/services/provider_execution/token_estimator.rb \
  app/services/provider_execution/prompt_budget_guard.rb \
  app/services/provider_execution/execute_round_loop.rb \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
git commit -m "feat: add provider prompt budget guard"
```

### Task 5: Add Runtime-First Compaction And Embedded Fallback

**Files:**
- Create: `core_matrix/app/services/provider_execution/prompt_compaction.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_compaction/agent_runtime_strategy.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_compaction/embedded_strategy.rb`
- Create: `core_matrix/app/services/embedded_agents/prompt_compaction/invoke.rb`
- Modify: `core_matrix/app/services/embedded_agents/registry.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Create: `core_matrix/test/services/embedded_agents/prompt_compaction/invoke_test.rb`

**Step 1: Write failing compaction-orchestration tests**

Extend `execute_round_loop_test.rb` so it expects:

- a soft-threshold crossing triggers compaction before provider dispatch
- runtime compaction may fall back to embedded compaction
- runtime-disabled or embedded-only policy modes honor the frozen prompt
  compaction policy from the execution snapshot

Create `embedded_agents/prompt_compaction/invoke_test.rb` with cases that
expect:

- the newest selected user message is preserved verbatim
- older transcript entries may be replaced by a bounded summary form
- the returned message list is suitable for the current round only

**Step 2: Implement the embedded fallback compactor**

Add `EmbeddedAgents::PromptCompaction::Invoke` and register it in
`EmbeddedAgents::Registry`.

Keep the implementation intentionally small:

- no durable transcript writes
- no new persistence models
- no recursive provider calls

**Step 3: Implement runtime-first compaction orchestration**

Add `ProviderExecution::PromptCompaction` that:

- prefers an agent-runtime `compact_context` execution through
  `AgentRequestExchange`
- falls back to the embedded compactor when runtime compaction is disabled,
  unavailable, or fails
- returns the replacement message list plus metadata about which strategy won

Use named constants for max attempts and never inline the retry counts.

**Step 4: Re-run the compaction-focused tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/embedded_agents/prompt_compaction/invoke_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Expected: the preflight compaction and embedded fallback cases now pass.

**Step 5: Commit**

```bash
git add \
  app/services/provider_execution/prompt_compaction.rb \
  app/services/provider_execution/prompt_compaction/agent_runtime_strategy.rb \
  app/services/provider_execution/prompt_compaction/embedded_strategy.rb \
  app/services/embedded_agents/prompt_compaction/invoke.rb \
  app/services/embedded_agents/registry.rb \
  app/services/provider_execution/execute_round_loop.rb \
  test/services/embedded_agents/prompt_compaction/invoke_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
git commit -m "feat: add prompt compaction fallback flow"
```

### Task 6: Classify Provider Overflow Explicitly And Persist User Recovery Metadata

**Files:**
- Modify: `core_matrix/app/services/provider_execution/failure_classification.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/app/services/workflows/block_node_for_failure.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Write failing overflow-recovery tests**

Extend `execute_round_loop_test.rb` so it expects:

- provider overflow triggers exactly one bounded re-entry through prompt
  compaction
- a second overflow fails with explicit prompt-size metadata instead of another
  retry loop

**Step 2: Implement explicit overflow detection in `FailureClassification`**

Add constants for known provider-overflow phrases and map matching HTTP errors
to:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

These should be manual-retry failures, not implementation errors.

**Step 3: Carry structured remediation metadata through failure persistence**

Extend failure persistence so the blocked workflow metadata includes:

- `retry_mode`
- `editable_tail_input`
- `failure_scope`
- `turn_id`
- `selected_input_message_id`

Use `Turns::EditTailInput` semantics to determine whether `edit_tail_input` is
valid for the failed turn.

**Step 4: Add one bounded provider-overflow recovery attempt**

Update `ExecuteRoundLoop` so a provider overflow may trigger exactly one
re-entry through prompt compaction before final failure.

Do not allow unlimited retry loops.

**Step 5: Run the targeted tests and make them green**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: overflow is classified explicitly, workflow failures persist
structured remediation payloads, and the bounded overflow-recovery path passes.

**Step 6: Commit**

```bash
git add \
  app/services/provider_execution/failure_classification.rb \
  app/services/provider_execution/persist_turn_step_failure.rb \
  app/services/workflows/block_node_for_failure.rb \
  app/services/provider_execution/execute_round_loop.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
git commit -m "feat: classify prompt overflow explicitly"
```

### Task 7: Run Verification And Close The Slice

**Files:**
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md`
- Modify: `core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md`

**Step 1: Run the focused `core_matrix` verification suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop -f github
bin/rails db:test:prepare
PARALLEL_WORKERS=1 bin/rails test \
  test/models/workspace_test.rb \
  test/requests/app_api/workspace_policies_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/embedded_agents/prompt_compaction/invoke_test.rb
```

Expected: green focused verification for the new prompt-budget protection
slice.

**Step 2: Run the broader `agents/fenix` verification commands required by repo policy**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

Expected: the Fenix-side manifest/config changes pass the owning project's
verification commands.

**Step 3: Run the broader `core_matrix` verification commands required by repo policy**

Run:

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

Expected: full `core_matrix` verification passes or any residual unrelated
failures are documented before merge.

**Step 4: Run the acceptance suite required for acceptance-critical loop changes**

Run from the monorepo root:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Expected:

- the acceptance suite passes
- relevant artifacts for provider-turn failure/recovery behavior are inspected
- resulting database state is checked to confirm prompt-size failures and wait
  states have the expected shapes

**Step 5: Update the docs only if implementation drifted from plan**

If file names, failure kinds, config keys, or workspace policy payload shape
changed during implementation, update both plan docs to match the shipped code
before handing off.

**Step 6: Commit**

```bash
git add \
  core_matrix/docs/plans/2026-04-14-prompt-budget-guard-design.md \
  core_matrix/docs/plans/2026-04-14-prompt-budget-guard-implementation.md
git commit -m "docs: finalize prompt budget guard plans"
```
