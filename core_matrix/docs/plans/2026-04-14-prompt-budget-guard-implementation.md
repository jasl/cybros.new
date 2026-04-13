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

## Current Baseline

This plan starts from the current code state, where the shared feature-policy
foundation already exists:

- `workspace.config.features.*` is the structured workspace policy container
- `WorkspaceFeatures::Schema` and `WorkspaceFeatures::Resolver` own feature
  normalization and effective resolution
- workspace policy show/update already exposes resolved `features.*`
- Fenix canonical config already ships `features.title_bootstrap` and
  `features.prompt_compaction`
- `ProviderExecution::PromptCompactionPolicy` already resolves the effective
  prompt-compaction policy
- `BuildExecutionSnapshot` already freezes
  `provider_context.feature_policies.prompt_compaction`
- `Conversations::Metadata::TitleBootstrapPolicy` intentionally remains a
  live-read feature on top of the same shared resolver

This implementation plan therefore covers only the remaining prompt-budget
guard work on top of that baseline.

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

### Task 2: Implement Token Estimation And Guard Decisions

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

Do not add compaction-orchestration expectations yet. Those belong to Task 3.

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
compaction orchestration is added in Task 3.

**Step 4: Wire the guard into `ExecuteRoundLoop` before dispatch**

Update `ExecuteRoundLoop` so it:

- assembles final provider messages
- calls `PromptBudgetGuard`
- dispatches only when the guard returns `allow`
- raises a typed local error when the guard returns `reject`
- raises a separate typed local error for `compact` until Task 3 implements the
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

### Task 3: Add Runtime-First Compaction And Embedded Fallback

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

### Task 4: Classify Provider Overflow Explicitly And Persist User Recovery Metadata

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

### Task 5: Run Verification And Close The Slice

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
  test/services/conversations/metadata/title_bootstrap_policy_test.rb \
  test/jobs/conversations/metadata/bootstrap_title_job_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/embedded_agents/prompt_compaction/invoke_test.rb
```

Expected:

- green focused verification for the new prompt-budget protection slice
- shared `features.*` regressions stay green
- title bootstrap retains its live-read behavior while prompt compaction stays
  snapshot-frozen

**Step 2: Re-run the Fenix manifest regression if any local implementation touched runtime config contracts**

Run only if the prompt-budget implementation changes `agents/fenix` config,
manifest packaging, or bundled-runtime defaults:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_manifest_test.rb
```

Expected: the Fenix manifest still exposes the shared `features.*` contract
used by `core_matrix`.

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
