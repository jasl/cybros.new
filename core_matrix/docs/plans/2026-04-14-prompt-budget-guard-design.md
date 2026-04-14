# Prompt Compaction Feature Slice Design

## Status

This document now describes the `prompt_compaction` feature slice on top of the
shared runtime feature platform defined in:

- [runtime-feature-platform-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md)

It no longer defines standalone infrastructure for policy, capability, or
runtime orchestration.

## Goal

Add authoritative prompt-budget protection for `core_matrix` turns by
implementing `prompt_compaction` as a first-class runtime feature:

- workspace policy controls strategy
- capability is manifest-driven
- execution is orchestrated by the shared platform
- model-backed compaction executes as workflow work, not as a hidden
  synchronous side effect
- runtime-backed compaction falls back to embedded compaction only as a
  degraded rescue path
- provider overflow becomes an explicit, user-recoverable failure

## Slice Scope

This slice is responsible for:

1. the `prompt_compaction` feature policy contract
2. the `prompt_compaction` runtime capability contract
3. the feature-specific orchestration and fallback behavior
4. integration with `ExecuteRoundLoop`
5. explicit overflow classification and remediation metadata

It depends on the shared platform for:

- policy schema publication
- capability resolution
- feature invocation
- runtime failure normalization

## Non-Goals

This slice does not:

- define the shared feature platform itself
- rewrite durable transcript history
- keep the legacy internal-tool abstraction as the long-term model
- make retry limits runtime-configurable
- make token estimation perfect for every provider family

## Feature Identity

Recommended registry identity:

- `feature_key`: `prompt_compaction`
- `runtime_capability_key`: `prompt_compaction`
- `runtime_requirement`: `required_on_fenix`
- `consultation_mode`: `direct_required`
- `policy_lifecycle`: `snapshot_frozen`
- `capability_lifecycle`: `snapshot_frozen`
- `default_strategy`: `runtime_first`
- `embedded_executor`: required

## Policy Contract

The feature policy should live under:

```json
{
  "features": {
    "prompt_compaction": {
      "strategy": "runtime_first"
    }
  }
}
```

Shared strategy meanings for this slice:

- `disabled`
  - do not attempt runtime or embedded compaction
  - prompt-budget guard may still reject clearly oversized requests
- `embedded_only`
  - use only embedded compaction
- `runtime_first`
  - consult and execute runtime-backed compaction when capability is present
  - fall back to embedded on supported fallback failures
- `runtime_required`
  - require runtime consultation and runtime execution success
  - do not fall back to embedded

## Capability Contract

Fenix manifest should advertise `prompt_compaction` through `feature_contract`,
not `tool_contract`.

The capability entry should include:

- `feature_key = "prompt_compaction"`
- `consultation_mode = "direct_required"`
- `execution_mode = "workflow_intent"`
- `lifecycle = "turn_scoped"`
- consultation schema for budget report plus compaction guidance
- intent schema for budget context and preservation invariants
- artifact schema for compacted payload plus diagnostics

For Fenix, this capability is not optional. Missing `prompt_compaction`
support should be treated as a runtime-contract defect, not as a normal
degraded mode.

## Prompt Construction Flow

The prompt-building flow should be modeled explicitly:

1. `PrepareAgentRound` asks the agent to build draft provider-visible messages
   and forwards a Core Matrix-owned budget envelope inside the existing
   `provider_context`
2. the runtime may use that envelope plus the input-token counting API to shape draft
   prompt construction more precisely without owning the final budget decision
3. Core Matrix appends prior-tool continuation entries and assembles the final
   provider request candidate
4. Core Matrix runs the authoritative token and reserve check
5. the guard decides one of:
   - `allow`
   - `consult`
   - `compact_required`
   - `reject`
6. when the result is `consult` or `compact_required`, Core Matrix asks the
   runtime agent for compaction guidance
7. if the final decision is to compact, Core Matrix inserts a
   `prompt_compaction` workflow node
8. if the consultation declines compaction and the request still satisfies the
   hard budget rules, Core Matrix may continue without compaction
9. if the consultation declines compaction but the request no longer satisfies
   the hard budget or reserve floor, Core Matrix fails explicitly
10. the node executes compaction, persists artifacts, and then re-enters the
   normal agent loop
11. the next loop iteration rebuilds the provider request using the compacted
   context

This keeps the authoritative trigger in Core Matrix while still letting the
runtime shape the compaction strategy.

## Budget Envelope During Prompt Construction

At prompt-construction time, Core Matrix should provide the runtime with a
stable budget envelope for the currently selected model so the agent can make
better drafting decisions before the final guard runs.

This envelope should be part of the normal round-construction payload, not an
ad hoc side channel.

Recommended shape:

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

Meanings:

- `recommended_input_tokens`
  - the budget Core Matrix wants the runtime to stay within for high-quality
    dispatch without needing compaction
- `reserved_tokens`
  - the total token budget Core Matrix intentionally withholds from prompt
    construction for output reserve and any safety buffer
- `hard_input_token_limit`
  - the largest prompt payload Core Matrix believes can still be dispatched for
    the selected model after output reserve is honored
- `provider_handle` / `model_ref` / `tokenizer_hint`
  - enough information for the runtime to reason about prompt shape and call
    the input-token counting API without independently owning tokenizer infrastructure

This envelope is guidance for prompt construction. It is not the final
preflight decision.

## Shared Input-Token Counting API

Beyond the automatic guard path, Core Matrix should expose a reusable
agent-facing input-token counting API over the authenticated AgentAPI surface
for agents that want to proactively manage how much context they include.

This API should:

- be Core Matrix-owned and authoritative
- reuse the same token-estimation and reserve logic as `PromptBudgetGuard`
- return advisory data only, not mutate workflow state
- complement the budget envelope already supplied during prompt construction
- be available to agents that want to proactively budget context for
  roleplay/chat or writing-heavy scenarios

Recommended result shape:

- `provider_handle`
- `model_ref`
- `api_model`
- `tokenizer_hint`
- `estimated_tokens`
- `remaining_tokens`
- `soft_threshold_tokens`
- `hard_context_limit`
- `recommended_input_tokens`
- `hard_input_token_limit`
- `reserved_tokens`
- `reserved_output_tokens`
- `decision_hint` (`allow`, `consult`, `compact_required`, `reject`)
- diagnostics

Recommended use:

- the budget envelope gives the agent static construction guidance up front
- the input-token counting API lets the agent re-check a concrete candidate
  prompt or candidate set of context inclusions while it is still drafting
- the final dispatch-time guard remains the only authoritative allow/compact/
  reject gate

Recommended transport:

- `POST /agent_api/responses/input_tokens`
- authenticated with the existing agent connection credential
- backed by the same estimator and reserve logic used by
  `PromptBudgetGuard`
- shaped after OpenAI's `POST /v1/responses/input_tokens` contract so the same
  endpoint can reason about multimodal provider-visible payloads

Recommended request shape:

- `provider_handle`
- `model_ref`
- `api_model` when needed by the resolved provider adapter
- `input`
  - using the same provider-visible content structure the runtime is preparing
    for dispatch
- optional candidate metadata such as selected input message id or context tags

The endpoint should accept the same broad classes of input payloads the final
provider request may contain, including text, images, file references, and
audio-bearing inputs when the selected provider/model supports them. This keeps
multimodal token accounting centralized in Core Matrix instead of pushing
format-specific counting logic into the runtime.

This API is advisory for prompt construction. It must not replace the final
dispatch-time guard.

## Consultation Contract

The actual LLM-backed compaction call should **not** go through synchronous
`execute_feature`, but Core Matrix should use a direct consultation request to
ask the runtime whether and how to compact.

The consultation payload should contain:

- final provider-visible messages
- `target_input_tokens`
- `hard_context_limit`
- `reserved_tokens`
- `reserved_output_tokens`
- hard and advisory budget hints
- model/tokenizer hints
- current selected input message identity
- feature policy snapshot
- preservation invariants
- compaction attempt counters
- the consultation reason (`soft_limit`, `reserve_risk`, `overflow_recovery`)

The consultation result should contain:

- `decision`
  - `skip`
  - `compact`
  - `reject`
- compaction strategy / style guidance
- prioritization hints
- preservation invariants
- diagnostics or rationale

## Workflow Execution Contract

Once consultation indicates compaction should happen, `prompt_compaction`
should be represented as workflow work:

1. Core Matrix materializes a dedicated `prompt_compaction` workflow node
2. the node executes compaction, persists artifacts, and then re-enters the
   normal agent loop

The node input payload should contain:

- final provider-visible messages
- consultation result payload
- `target_input_tokens`
- `hard_context_limit`
- `reserved_tokens`
- `reserved_output_tokens`
- current selected input message identity
- feature policy snapshot
- preservation invariants

The workflow-node artifact/result should contain:

- replacement messages
- whether compaction changed anything
- optional compaction diagnostics
- `estimated_tokens_before`
- `estimated_tokens_after`
- `estimator_strategy`
- `stop_reason`
- `source`
- `fallback_used`
- estimator metadata

## Slice-Specific Lifecycle Rules

`prompt_compaction` is execution-critical and must run against the exact turn
state that was frozen before provider dispatch.

That means:

- policy is resolved once and frozen
- capability is resolved once and frozen
- compaction consultation and node execution run against the frozen
  provider-visible round payload

This feature must not read live workspace policy while a turn is already in
flight.

## Implementation Strategy Informed By Reference Systems

The intended behavior here should follow the strongest common patterns from the
reference systems we already reviewed:

- Claude Code and OpenClaw both do preflight budgeting before provider dispatch
  and compact before hitting a hard overflow path.
- Codex and Claude Code preserve the newest user input and compact older
  history instead of rewriting the current request.
- OpenClaw aggressively targets bulky tool outputs and other non-primary
  context first, which is the right bias for maintaining agent quality.
- All three use bounded overflow recovery rather than open-ended retry loops.

That gives the slice these concrete requirements:

- budget before dispatch using soft and hard thresholds
- preserve the newest selected user input verbatim
- compact older transcript, imports, and oversized tool outputs first
- retry once after explicit provider overflow, then fail explicitly
- return compaction diagnostics instead of silently degrading behavior

The preservation contract should explicitly require that compaction keeps:

- the current user goal/request
- explicit user constraints and prohibitions
- referenced file paths, resources, and identifiers still needed for execution
- unresolved errors, blockers, and failure context
- pending tool outcomes or follow-up obligations
- the active working plan or next-step queue when one exists

For v1, the actual compaction strategy should be intentionally redundant:

- Core Matrix embedded compaction and Fenix workflow-node compaction should
  share the same baseline preservation and reduction rules
- the two paths should be kept behaviorally aligned through shared fixtures or
  golden tests
- Fenix may later evolve a more scenario-specific algorithm, but the initial
  implementation should not diverge gratuitously from the embedded fallback

## Runtime And Embedded Behavior

### Runtime Path

When policy allows runtime execution and the frozen capability snapshot
advertises `prompt_compaction`, the platform should prefer runtime-authored
consultation plus runtime-backed workflow execution first.

For Fenix, this is the expected quality path, not an optional optimization.
That does not mean Fenix owns the authoritative budget calculation. Core Matrix
does. Fenix participates by:

1. advertising the capability
2. responding to compaction consultation requests
3. executing the compaction workflow node when Core Matrix inserts it

### Embedded Path

Embedded compaction is required for product resilience.

The embedded executor should:

- preserve the newest selected user input verbatim
- compact older context only
- avoid durable transcript writes
- produce a replacement message list for the current round only

For Fenix, embedded compaction is an emergency fallback and must not be treated
as quality-equivalent to the runtime implementation.

### Runtime Failure Handling

The runtime path should fall back to embedded compaction when strategy permits
and the normalized platform failure is one of:

- `feature_not_advertised`
- `feature_unsupported`
- `feature_timeout`
- `feature_runtime_error`

`runtime_required` should not fall back.

For Fenix specifically, `feature_not_advertised` should be prevented by
manifest and bundled-runtime contract tests. If it still appears at runtime, it
should be treated as a contract breach with degraded fallback, not as a normal
steady-state path.

Any Fenix-backed fallback to embedded compaction should be observable in
artifacts or failure metadata through at least:

- `source = "embedded"`
- `fallback_used = true`
- `runtime_failure_code`

## Guard Integration

`ProviderExecution::ExecuteRoundLoop` should remain the final authority before
provider dispatch.

The slice-specific logic should be:

1. estimate prompt tokens
2. decide `allow`, `consult`, `compact_required`, or `reject`
3. consult the runtime when the decision is `consult` or `compact_required`
4. materialize a `prompt_compaction` workflow node when the final decision is
   to compact
5. re-estimate after the node completes
6. dispatch only when the request fits

The feature platform owns compaction orchestration; the guard owns the dispatch
decision.

## Provider Overflow Recovery

Preflight estimation can still miss.

The slice should allow one bounded recovery loop:

1. provider returns explicit overflow
2. the round re-enters compaction mode
3. Core Matrix consults the runtime again with `consultation_reason =
   "overflow_recovery"`
4. a `prompt_compaction` workflow node runs again when the result says to
   compact
5. provider request retries once

If the second attempt still overflows, the round fails explicitly.

## Failure Semantics

This slice should map prompt-size failures into explicit product failures such
as:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

The failure payload should include:

- `retry_mode`
- `editable_tail_input`
- `failure_scope`
- `turn_id`
- `selected_input_message_id`

## Testing Focus

Prompt compaction should be tested at four levels:

1. feature slice policy and capability projection
2. workflow intent materialization, workflow node execution, and runtime vs
   embedded fallback
3. guard integration and bounded overflow recovery
4. workflow failure payload, artifacts, and user remediation metadata

## Summary

`prompt_compaction` should no longer behave like a special-case internal tool.
It should be implemented as a first-class runtime feature slice:

- snapshot-frozen
- runtime-first
- workflow-backed
- embedded-backed
- execution-critical
- explicitly recoverable when provider overflow occurs
