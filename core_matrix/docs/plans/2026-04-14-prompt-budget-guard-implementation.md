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
- model-backed compaction is represented as workflow work
- Fenix is required to implement prompt-compaction consultation and workflow
  execution support
- missing or failing runtime support falls back to embedded compaction when the
  frozen strategy allows it
- provider overflow becomes a typed, user-recoverable failure instead of
  `internal_unexpected_error`

## Architecture

`ProviderExecution::ExecuteRoundLoop` remains the final authority before
provider dispatch. The slice-specific pieces are:

- `ProviderExecution::TokenEstimator`
- `ProviderExecution::PromptBudgetGuard`
- workflow-intent materialization for `prompt_compaction`
- provider-overflow recovery and failure classification

The shared platform owns:

- policy schema under `features.prompt_compaction`
- capability resolution from `feature_contract`
- direct invocation only for direct features; `prompt_compaction` does not use
  synchronous `execute_feature`
- workflow-backed feature execution and embedded fallback selection
- runtime failure normalization

For this slice, Fenix is the primary runtime implementation, not an optional
capability provider.

## Target Outcome

At the end of this plan:

- oversized turns are caught before provider dispatch whenever possible
- the newest selected user input is never compacted away
- Core Matrix is the sole trigger for prompt compaction
- prompt construction receives a Core Matrix-owned budget envelope for the
  selected model and available prompt budget
- Fenix advertises `prompt_compaction`, responds to compaction consultations,
  and executes the compaction workflow node as a required capability
- the actual LLM compaction call appears as a workflow node
- `runtime_first` prefers runtime compaction but only degrades to embedded on
  bounded runtime failure
- `runtime_required` fails explicitly when runtime capability is missing or the
  runtime compaction request fails
- prompt-size failures persist structured remediation metadata that the app can
  use to guide retry

## Task Boundaries

This slice owns:

- token estimation
- guard decisions
- prompt-construction budget envelope publication
- the shared input-token counting API for proactive agent use
- compaction workflow-node integration into round execution
- bounded overflow recovery
- prompt-size failure payloads

This slice does not own:

- policy schema infrastructure
- feature registry or capability registry
- generic feature orchestration semantics

This slice does own the concrete Fenix `prompt_compaction` capability because
quality depends on it, but that capability is split between direct
consultation and workflow-backed execution rather than a single synchronous
direct feature RPC.

---

### Task 1: Lock Slice Contracts Before Wiring Round Execution

**Files:**
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/respond_to_consultation_test.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/execute_node_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Modify: `agents/fenix/test/services/build_round_instructions_test.rb`
- Modify: `agents/fenix/test/services/requests/prepare_round_test.rb`
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Create: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/provider_execution/build_request_context_test.rb`

**Step 1: Write failing `TokenEstimator` tests**

Cover the estimator fallback chain:

- exact local tokenizer asset wins when available
- `tiktoken` is used when no exact asset exists
- heuristic fallback is used when neither tokenizer path is available
- heuristic fallback intentionally over-estimates instead of under-estimating

**Step 2: Write failing `PromptBudgetGuard` tests**

Cover the four decision states:

- `allow` below the soft threshold
- `consult` when the request crosses the soft threshold or output reserve risk
  appears but hard limits still allow a decision
- `compact_required` when the request no longer fits and compaction is the only
  remaining recovery path
- `reject` when the newest selected user input alone exceeds the remaining hard
  budget

Also assert remediation metadata for:

- `failure_scope = "current_message"`
- `failure_scope = "full_context"`
- `retry_mode`

**Step 3: Write failing round-loop integration tests**

Extend `execute_round_loop_test.rb` so it expects:

- dispatch proceeds when the guard returns `allow`
- the round consults Fenix when the guard returns `consult`
- the round consults and then materializes `prompt_compaction` workflow work
  when the final decision is to compact
- the round may continue without compaction when consultation returns `skip`
  and the request still fits hard-budget rules
- the round raises a typed local failure when the guard returns `reject`

Stub the consultation and workflow-materialization boundaries. Do not duplicate
platform fallback tests here.

**Step 4: Write failing prompt-construction envelope tests**

Extend `prepare_agent_round_test.rb`, `build_execution_snapshot_test.rb`,
`build_round_instructions_test.rb`, and Fenix `prepare_round_test.rb` so they
expect prompt construction to
receive a Core Matrix-owned budget envelope through the existing
`provider_context`.

Assert that:

- `provider_context.model_context` carries selected model identity
  (`provider_handle`, `model_ref`, `api_model`, `tokenizer_hint`)
- `provider_context.budget_hints.hard_limits` carries
  `hard_input_token_limit`
- `provider_context.budget_hints.advisory_hints` carries
  `recommended_input_tokens`, `reserved_tokens`, `reserved_output_tokens`, and
  `soft_threshold_tokens`
- Fenix prompt construction can observe those fields without inventing its own
  budgeting source of truth

Also assert that this envelope is static build guidance and that dynamic budget
re-checks still belong to the input-token counting API.

**Step 5: Write failing Fenix contract tests**

Add expectations that:

- Fenix manifest always advertises `prompt_compaction`
- prompt compaction declares `consultation_mode = direct_required`
- prompt compaction declares `execution_mode = workflow_intent`
- Fenix can respond to compaction consultations
- Fenix can execute the compaction workflow node
- missing prompt-compaction support is treated as a test failure, not as an
  allowed optional capability

**Step 6: Write failing overflow-classification tests**

Extend `failure_classification_test.rb` so it expects:

- HTTP `413` maps to a prompt-size failure
- HTTP `400` / `422` bodies containing `prompt too long`, `context length`,
  `maximum context length`, or `request too large` also map to prompt-size
  failures
- these failures are retryable by user action, not generic implementation
  failures

**Step 7: Write failing failure-persistence tests**

Extend `execute_turn_step_test.rb` so persisted failure payloads include:

- `retry_mode`
- `editable_tail_input`
- `failure_scope`
- `turn_id`
- `selected_input_message_id`
- fallback source / degraded-runtime diagnostics when applicable

**Step 8: Run the targeted tests and verify they fail**

From `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/build_request_context_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/build_round_instructions_test.rb \
  test/services/requests/prepare_round_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/features/prompt_compaction/respond_to_consultation_test.rb \
  test/services/features/prompt_compaction/execute_node_test.rb
```

Expected: failures show the estimator and guard do not exist yet, round
execution does not materialize compaction workflow work, Fenix does not yet
implement the required runtime capability, and overflow is still classified
generically.

### Task 2: Implement Fenix Consultation And Workflow Execution

**Files:**
- Create: `agents/fenix/app/services/features/prompt_compaction/respond_to_consultation.rb`
- Create: `agents/fenix/app/services/features/prompt_compaction/execute_node.rb`
- Modify: `agents/fenix/app/services/requests/execute_feature.rb`
- Modify: `agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/respond_to_consultation_test.rb`
- Create: `agents/fenix/test/services/features/prompt_compaction/execute_node_test.rb`

**Step 1: Implement the consultation responder**

Add a direct consultation handler that consumes the Core Matrix budget report
and returns compaction guidance.

Its algorithm should be informed by the patterns we saw in Claude Code, Codex,
and OpenClaw:

- use Core Matrix budget diagnostics as authoritative input
- preserve the newest selected user input verbatim
- compact older history and imports before touching recent user context
- aggressively reduce bulky tool results before compacting primary transcript
- prepare explicit diagnostics and preservation invariants

The responder should return:

- `decision` (`skip`, `compact`, `reject`)
- compaction strategy / style guidance
- prioritization hints
- preservation invariants
- diagnostics / rationale

**Step 2: Implement workflow-node execution**

Implement the actual compaction execution for the materialized workflow node.

It should not invent open-ended recursive summarization loops.
For v1, keep its strategy intentionally aligned with the embedded fallback:

- same preservation invariants
- same prioritization of bulky tool outputs before primary transcript
- same stop conditions and diagnostics shape

Back this with shared fixtures or golden tests so runtime and embedded paths do
not drift accidentally.

**Step 3: Wire Fenix manifest and direct consultation support**

Make `prompt_compaction`:

- advertised in `feature_contract`
- declared as `consultation_mode = direct_required`
- declared as `execution_mode = workflow_intent`
- treated as required by Fenix integration tests

**Step 4: Run the targeted Fenix tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/features/prompt_compaction/respond_to_consultation_test.rb \
  test/services/features/prompt_compaction/execute_node_test.rb
```

Expected: Fenix now provides the required consultation and workflow execution
path for prompt compaction.
### Task 3: Implement Token Estimation And Guard Decisions

**Files:**
- Create: `core_matrix/app/services/provider_execution/token_estimator.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_budget_advisory.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/provider_execution/build_request_context.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/agent_api/responses/input_tokens_controller.rb`
- Modify: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_advisory_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/provider_execution/build_request_context_test.rb`
- Create: `core_matrix/test/requests/agent_api/responses/input_tokens_test.rb`
- Modify: `agents/fenix/app/services/shared/control_plane/client.rb`
- Modify: `agents/fenix/test/services/shared/control_plane/client_test.rb`
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

**Step 2: Publish prompt-construction budget envelope**

Update `BuildExecutionSnapshot` so the existing `provider_context` carries a
stable Core Matrix-owned budget envelope before `PrepareAgentRound` forwards it
to the runtime.

The envelope should be expressed through:

- `provider_context.model_context`
  - `provider_handle`
  - `model_ref`
  - `api_model`
  - `tokenizer_hint`
- `provider_context.budget_hints.hard_limits`
  - `context_window_tokens`
  - `max_output_tokens`
  - `hard_input_token_limit`
- `provider_context.budget_hints.advisory_hints`
  - `recommended_compaction_threshold`
  - `recommended_input_tokens`
  - `reserved_tokens`
  - `reserved_output_tokens`
  - `soft_threshold_tokens`
  - `context_soft_limit_ratio`

Add targeted tests that prove:

- the envelope is produced in `BuildExecutionSnapshot`
- `PrepareAgentRound` forwards it without reshaping it
- `BuildRequestContext` still exposes the correct dispatch-time hard/advisory
  limits for the final guard
- the envelope reflects the selected model definition
- the envelope exposes recommended and hard prompt-input budgets distinctly
- the input-token counting API remains a separate dynamic recalculation path

**Step 3: Implement `PromptBudgetGuard`**

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

Decision meanings should be explicit:

- `allow`
- `consult`
- `compact_required`
- `reject`

**Step 4: Expose shared input-token counting API**

Implement a Core Matrix-owned input-token counting service that reuses the same
estimator and budget rules but returns diagnostics without mutating workflow
state.

This service should be usable by agents that want to proactively manage context
volume in scenarios such as roleplay or long-form writing. It remains advisory
for prompt construction and must not replace the final dispatch-time guard.

Expose it through an authenticated AgentAPI endpoint, for example:

- `POST /agent_api/responses/input_tokens`

The endpoint contract should accept:

- selected model identity or a resolvable provider/model reference
- `input` payload using the same provider-visible message/content structure the
  runtime is preparing for dispatch
- optional candidate context metadata used for diagnostics

The endpoint should be designed to support multimodal provider-visible payloads
so token counting for text, image, file, and audio-bearing inputs stays
centralized in Core Matrix rather than being reimplemented in runtimes.

The response should echo:

- selected model identity
- the effective recommended / hard prompt-input budget
- `reserved_tokens`
- estimated token usage for the candidate payload
- decision hint and diagnostics

Fenix should gain a small control-plane client wrapper for this endpoint so the
runtime can query it while drafting prompts.

**Step 5: Gate round execution before dispatch**

Update `ExecuteRoundLoop` so it:

- assembles the final provider-visible message list
- runs `PromptBudgetGuard`
- dispatches only on `allow`
- routes `consult` into the compaction-consultation path
- routes `compact_required` into consultation followed by mandatory workflow
  insertion
- continues after `consult` when the consultation returns `skip` and the
  request still satisfies hard-budget rules
- raises a typed local rejection on `reject`

At this stage, keep the compaction integration minimal and deterministic. The
platform should be treated as a dependency boundary, not reimplemented here.
The guard remains the single authoritative preflight decision-maker.

**Step 6: Run the targeted test set and make it green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/prompt_budget_advisory_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/build_request_context_test.rb \
  test/requests/agent_api/responses/input_tokens_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/build_round_instructions_test.rb \
  test/services/requests/prepare_round_test.rb \
  test/services/shared/control_plane/client_test.rb
```

Expected: estimation and guard decisions are now authoritative before provider
dispatch.

### Task 4: Integrate Platform-Driven Compaction And Bounded Recovery

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`

**Step 1: Add failing compaction-integration tests**

Extend `execute_round_loop_test.rb` so it expects:

- the runtime is consulted when the guard returns `consult`
- a `prompt_compaction` workflow node or equivalent materialization request is
  created when the consultation result says to compact or when compaction is
  mandatory
- the frozen policy and frozen capability snapshot are used
- runtime-first compaction may fall back through the platform to embedded
  compaction when the normalized platform result allows it
- the compacted message list is re-estimated before dispatch
- the workflow path re-enters the normal agent loop after compaction
- degraded Fenix fallback is observable through `source`, `fallback_used`, and
  `runtime_failure_code`

These tests should stub the platform result shape instead of retesting platform
internals.

**Step 2: Wire consultation, workflow insertion, and re-entry**

Update `ExecuteRoundLoop` so the guarded compaction path:

- consults the runtime first
- materializes or requests `prompt_compaction` workflow work when the final
  decision is to compact
- continues without compaction when the consultation result is `skip` and the
  request still fits
- passes the final provider-visible messages plus budget context
- replaces only the current round payload
- preserves the newest selected input message verbatim
- carries forward node/artifact diagnostics including before/after estimates

**Step 3: Add bounded provider-overflow recovery**

Allow one explicit recovery loop when the provider still returns overflow:

1. classify the provider error as prompt-size overflow
2. re-enter compaction mode
3. consult the runtime again with `consultation_reason = "overflow_recovery"`
4. materialize the `prompt_compaction` workflow path again when the result says
   to compact
5. retry provider dispatch once

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

In Fenix-backed runs, this path should treat runtime compaction as the expected
quality path. Embedded compaction remains available only as a degraded rescue.

### Task 5: Persist Explicit Prompt-Size Failures And Remediation Metadata

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
- whether the run degraded from runtime to embedded compaction
- the normalized runtime failure code when degraded fallback occurred

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: prompt-size failures are explicit, recoverable, and app-readable.

### Task 6: Verify The Slice End To End

**Files:**
- Modify as needed: prompt-compaction docs or tests discovered during cleanup
- Create/Modify as needed: integration or acceptance tests using tiny-context
  provider definitions and fake adapters

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

Then run the focused Fenix verification:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/features/prompt_compaction/respond_to_consultation_test.rb \
  test/services/features/prompt_compaction/execute_node_test.rb
```

**Step 1.5: Add a deterministic e2e path without real large-window models**

Add one end-to-end test path that forces compaction deterministically by
shrinking the model budget instead of relying on a real provider with a huge
context window.

Recommended strategy:

- use the existing fake/mock provider adapters under `core_matrix/test/support`
- register a tiny test model definition with a very small
  `context_window_tokens` and `max_output_tokens`
- drive a turn through `PrepareAgentRound -> PromptBudgetGuard -> consultation ->
  workflow node -> re-entry`
- assert the workflow node/artifacts/failure metadata shape directly

Prefer this over real-LLM tests. If an acceptance-style path is needed, keep it
behind the same fake-provider approach so the test stays deterministic and
cheap.

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

Then run full `agents/fenix` verification because this slice requires a real
runtime implementation:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
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
