# Prompt Compaction Feature Slice Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Status

This document now describes the `prompt_compaction` feature slice on top of
the shared platform defined in:

- [runtime-feature-platform-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md)
- [runtime-feature-platform-implementation.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-implementation.md)

If the platform is being implemented in the same stream, complete platform
Tasks 1 through 6 first. This slice should not reintroduce feature-specific
policy resolution, manifest parsing, or `execute_tool`-shaped runtime calls.

## Goal

Add authoritative prompt-budget protection for provider turns by implementing
`prompt_compaction` as an execution-critical feature slice:

- token budgets are checked before dispatch
- compaction policy is frozen per turn
- runtime compaction is attempted only through the feature platform
- missing or failing runtime support falls back to embedded compaction when the
  frozen strategy allows it
- provider overflow becomes a typed, user-recoverable failure instead of
  `internal_unexpected_error`

## Architecture

`ProviderExecution::ExecuteRoundLoop` remains the final authority before
provider dispatch. The slice-specific pieces are:

- `ProviderExecution::TokenEstimator`
- `ProviderExecution::PromptBudgetGuard`
- integration with `RuntimeFeatures::Invoke` for `prompt_compaction`
- provider-overflow recovery and failure classification

The shared platform owns:

- policy schema under `features.prompt_compaction`
- capability resolution from `feature_contract`
- runtime invocation through `execute_feature`
- runtime failure normalization

## Target Outcome

At the end of this plan:

- oversized turns are caught before provider dispatch whenever possible
- the newest selected user input is never compacted away
- `runtime_first` prefers runtime compaction but cleanly falls back to embedded
- `runtime_required` fails explicitly when runtime capability is missing or the
  runtime compaction request fails
- prompt-size failures persist structured remediation metadata that the app can
  use to guide retry

## Task Boundaries

This slice owns:

- token estimation
- guard decisions
- compaction integration into round execution
- bounded overflow recovery
- prompt-size failure payloads

This slice does not own:

- policy schema infrastructure
- feature registry or capability registry
- Fenix `feature_contract` transport
- generic feature orchestration semantics

---

### Task 1: Lock Slice Contracts Before Wiring Round Execution

**Files:**
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Create: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Write failing `TokenEstimator` tests**

Cover the estimator fallback chain:

- exact local tokenizer asset wins when available
- `tiktoken` is used when no exact asset exists
- heuristic fallback is used when neither tokenizer path is available
- heuristic fallback intentionally over-estimates instead of under-estimating

**Step 2: Write failing `PromptBudgetGuard` tests**

Cover the three decision states:

- `allow` below the soft threshold
- `compact` when the request crosses the soft threshold
- `reject` when the newest selected user input alone exceeds the remaining hard
  budget

Also assert remediation metadata for:

- `failure_scope = "current_message"`
- `failure_scope = "full_context"`
- `retry_mode`

**Step 3: Write failing round-loop integration tests**

Extend `execute_round_loop_test.rb` so it expects:

- dispatch proceeds when the guard returns `allow`
- the round calls `RuntimeFeatures::Invoke` with
  `feature_key = "prompt_compaction"` when the guard returns `compact`
- the round raises a typed local failure when the guard returns `reject`

Stub the platform invocation boundary. Do not duplicate platform fallback
tests here.

**Step 4: Write failing overflow-classification tests**

Extend `failure_classification_test.rb` so it expects:

- HTTP `413` maps to a prompt-size failure
- HTTP `400` / `422` bodies containing `prompt too long`, `context length`,
  `maximum context length`, or `request too large` also map to prompt-size
  failures
- these failures are retryable by user action, not generic implementation
  failures

**Step 5: Write failing failure-persistence tests**

Extend `execute_turn_step_test.rb` so persisted failure payloads include:

- `retry_mode`
- `editable_tail_input`
- `failure_scope`
- `turn_id`
- `selected_input_message_id`

**Step 6: Run the targeted tests and verify they fail**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: failures show the estimator and guard do not exist yet, round
execution does not invoke the feature platform, and overflow is still
classified generically.

### Task 2: Implement Token Estimation And Guard Decisions

**Files:**
- Create: `core_matrix/app/services/provider_execution/token_estimator.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Implement `TokenEstimator`**

The estimator should accept:

- final provider-visible messages
- model or tokenizer hints
- the relevant hard-budget context

It should return:

- `estimated_tokens`
- `strategy`
- any useful diagnostics for logging

Fallback order:

1. exact local tokenizer asset
2. `tiktoken`
3. heuristic estimate

**Step 2: Implement `PromptBudgetGuard`**

Add explicit constants, not inline magic numbers, for:

- soft-budget reserve behavior
- heuristic safety multiplier or buffer
- max compaction attempts
- max overflow-recovery attempts

The guard result should expose at least:

- `decision`
- `estimated_tokens`
- `estimator_strategy`
- `failure_scope`
- `retry_mode`

**Step 3: Gate round execution before dispatch**

Update `ExecuteRoundLoop` so it:

- assembles the final provider-visible message list
- runs `PromptBudgetGuard`
- dispatches only on `allow`
- routes `compact` into the feature-platform path
- raises a typed local rejection on `reject`

At this stage, keep the compaction integration minimal and deterministic. The
platform should be treated as a dependency boundary, not reimplemented here.

**Step 4: Run the targeted test set and make it green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Expected: estimation and guard decisions are now authoritative before provider
dispatch.

### Task 3: Integrate Platform-Driven Compaction And Bounded Recovery

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`

**Step 1: Add failing compaction-integration tests**

Extend `execute_round_loop_test.rb` so it expects:

- `RuntimeFeatures::Invoke` is called with `feature_key = "prompt_compaction"`
- the frozen policy and frozen capability snapshot are used
- runtime-first compaction may fall back through the platform to embedded
  compaction when the normalized platform result allows it
- the compacted message list is re-estimated before dispatch

These tests should stub the platform result shape instead of retesting platform
internals.

**Step 2: Wire the slice to the platform**

Update `ExecuteRoundLoop` so the `compact` path:

- invokes `RuntimeFeatures::Invoke`
- passes the final provider-visible messages plus budget context
- replaces only the current round payload
- preserves the newest selected input message verbatim

**Step 3: Add bounded provider-overflow recovery**

Allow one explicit recovery loop when the provider still returns overflow:

1. classify the provider error as prompt-size overflow
2. re-enter compaction mode
3. invoke `prompt_compaction` again
4. retry provider dispatch once

Stop after the hard attempt limit. Do not allow open-ended compaction cycles.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Expected: prompt compaction now flows through the shared feature platform with
bounded retry behavior.

### Task 4: Persist Explicit Prompt-Size Failures And Remediation Metadata

**Files:**
- Modify: `core_matrix/app/services/provider_execution/failure_classification.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Step 1: Classify prompt-size failures explicitly**

Map local and provider-side overflow signals into dedicated failure kinds such
as:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

Do not route these failures through `internal_unexpected_error`.

**Step 2: Persist remediation metadata**

Persist enough information for the app surface to drive retry UX:

- whether the tail input is editable
- whether the user must send a new message
- whether the failure is caused by the current message alone or full context
- the selected input message identity

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: prompt-size failures are explicit, recoverable, and app-readable.

### Task 5: Verify The Slice End To End

**Files:**
- Modify as needed: prompt-compaction docs or tests discovered during cleanup

**Step 1: Run focused slice verification**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

**Step 2: Run full `core_matrix` verification required by repo policy**

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

**Step 3: Run acceptance verification because this touches acceptance-critical turn behavior**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Inspect both:

- acceptance artifacts relevant to provider-turn failure handling
- resulting database state for failure payload shape and turn-step transitions

Expected: prompt compaction behaves as a feature slice on top of the platform,
and acceptance-critical loop behavior remains correct.
