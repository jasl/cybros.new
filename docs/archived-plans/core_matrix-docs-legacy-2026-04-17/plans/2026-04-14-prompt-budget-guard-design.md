# Prompt Budget Guard And Request Preparation Design

## Status

This document no longer models `prompt_compaction` as a normal runtime feature
slice.

The long-term architecture is:

- `title_bootstrap` and similar product features live on the runtime feature
  platform
- prompt-budget protection and Core Matrix-assisted compaction live in a
  dedicated request-preparation subsystem

Related platform document:

- [2026-04-14-runtime-feature-platform-design.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-14-runtime-feature-platform-design.md)

## Goal

Add authoritative prompt-budget protection for `core_matrix` turns with a
dedicated request-preparation subsystem that:

- gives light agents a working Core Matrix fallback
- gives sophisticated agents better control during prompt construction
- keeps Core Matrix as the sole authoritative dispatch-time budget gate
- records all Core Matrix-assisted compaction as workflow work
- turns provider overflow into explicit, user-recoverable failures

## Product Constraints

This design must satisfy two product constraints.

### 1. Agent Freedom

Agents may be simple or sophisticated.

Simple agents should still work because Core Matrix provides:

- a budget envelope during prompt construction
- authoritative budget guarding before dispatch
- embedded compaction fallback

Sophisticated agents may do more on their own, including:

- local token estimation
- local prompt trimming
- local compaction before the draft is handed back to Core Matrix

Core Matrix does not try to forbid those local choices.

### 2. Core Matrix Assistance Must Be Workflow-Visible

If the agent asks Core Matrix to help with compaction, or if Core Matrix
decides it must intervene, that assistance must:

- be materialized as workflow work
- be scheduled by the workflow engine
- persist artifacts and diagnostics
- re-enter the normal agent loop afterward

Read-only budgeting help is different:

- `POST /agent_api/responses/input_tokens` is advisory infrastructure
- it does not mutate workflow state
- it does not count as compaction assistance

## Scope

This subsystem owns:

1. budget-envelope production during prompt construction
2. agent-facing input-token counting
3. token estimation and reserve calculation
4. authoritative dispatch-time budget guarding
5. request-preparation runtime capability discovery for prompt compaction
6. compaction consultation
7. compaction workflow-node execution
8. bounded overflow recovery
9. explicit failure and remediation metadata

It does not own:

- generic runtime feature execution
- title-bootstrap policy or invocation
- agent-local prompt shaping that never asks Core Matrix for help

## Shared Settings Contract

`prompt_compaction` should keep using the shared workspace policy namespace:

```json
{
  "features": {
    "prompt_compaction": {
      "strategy": "runtime_first"
    }
  }
}
```

Shared strategy meanings for this subsystem:

- `disabled`
  - do not attempt Core Matrix-assisted compaction
  - still reject obviously oversized requests when necessary
- `embedded_only`
  - use only Core Matrix embedded compaction when compaction is needed
- `runtime_first`
  - prefer runtime-authored consultation and runtime-backed workflow execution
  - fall back to embedded when policy allows and runtime fails
- `runtime_required`
  - require runtime consultation and runtime-backed workflow execution
  - do not fall back to embedded

The policy schema may be published by the shared `features.*` schema layer, but
execution remains request-preparation-specific.

For execution semantics, effective `prompt_compaction` policy should be
resolved and frozen per prepared round. The guard, consultation path,
workflow-node execution, and overflow recovery loop should all operate against
that frozen turn-scoped policy, not live workspace reads.

## Dedicated Request-Preparation Capability Contract

Prompt compaction should not be advertised through the runtime-feature
platform's `feature_contract`.

Instead, Fenix manifest should gain a separate top-level contract, for example:

- `request_preparation_contract`

The initial entry should be:

```json
{
  "prompt_compaction": {
    "consultation_mode": "direct_optional",
    "workflow_execution": "supported",
    "lifecycle": "turn_scoped",
    "consultation_schema": { "type": "object" },
    "artifact_schema": { "type": "object" },
    "implementation_ref": "fenix/prompt_compaction"
  }
}
```

Interpretation:

- `consultation_mode`
  - whether Core Matrix may ask the agent for compaction guidance before
    materializing workflow work
- `workflow_execution`
  - whether the runtime can execute the materialized compaction node
- `lifecycle = turn_scoped`
  - capability is evaluated against the current prepared round / runtime

The effective runtime capability should be frozen alongside the prepared round
so consultation, workflow execution, and overflow recovery all operate against
the same turn-scoped contract.

For Fenix:

- `prompt_compaction` support is expected
- missing capability is a contract defect
- embedded fallback remains available as degraded rescue, not as quality
  equivalence

For other runtimes:

- the capability may be absent
- Core Matrix embedded compaction remains a valid fallback path

## Request-Preparation Transport

Runtime participation in prompt compaction should use the existing
`agent_request` control plane, not `execution_assignment`.

This is important because Fenix is agent-only today:

- `prepare_round` already runs over `agent_request`
- Fenix currently rejects `execution_assignment`
- prompt compaction is still agent-authored work even when it is scheduled by
  the workflow engine

Recommended request kinds:

- `consult_prompt_compaction`
  - direct consultation only
  - no workflow mutation
- `execute_prompt_compaction`
  - executes the materialized `prompt_compaction` workflow node

Core Matrix should introduce a dedicated request-preparation exchange on top of
the existing mailbox primitives rather than overloading `execute_feature` or
execution-runtime assignment.

## Prompt Construction Flow

The request-preparation flow should be explicit:

1. `PrepareAgentRound` asks the agent to build a draft provider-visible input
   payload
2. Core Matrix includes a stable budget envelope in `provider_context`
3. the agent may:
   - use the budget envelope only
   - call `POST /agent_api/responses/input_tokens`
   - do additional local estimation or trimming on its own
4. the agent returns a draft input candidate to Core Matrix
5. Core Matrix appends continuation or prior-tool context and assembles the
   final provider request candidate
6. Core Matrix runs the authoritative budget guard
7. the guard returns one of:
   - `allow`
   - `consult`
   - `compact_required`
   - `reject`
8. if the result is `consult` or `compact_required`, Core Matrix may ask the
   runtime for compaction guidance when runtime consultation is available and
   policy allows it
9. Core Matrix decides whether to:
   - continue as-is
   - insert a `prompt_compaction` workflow node
   - reject explicitly
10. if a workflow node is inserted, the workflow engine executes it using
    runtime-backed or embedded compaction
11. the node persists artifacts and diagnostics
12. the workflow re-enters the normal agent loop
13. the next loop iteration rebuilds provider-visible input using the compacted
    context

Only Core Matrix may materialize Core Matrix-assisted compaction workflow work.

## Workflow Fusion With The Agent Loop

The current workflow engine already knows how to:

- execute `turn_step`
- execute `tool_call`
- schedule runnable successors through graph edges

Prompt compaction should integrate with that model directly instead of
inventing a side channel.

Recommended graph shape when compaction is chosen:

1. the current `turn_step` completes with a yielded compaction outcome
2. Core Matrix materializes a `prompt_compaction` node
3. Core Matrix materializes a successor `turn_step` node
4. edges become:
   - current `turn_step` -> `prompt_compaction`
   - `prompt_compaction` -> successor `turn_step`
5. the workflow engine dispatches the `prompt_compaction` node
6. after compaction completes, the successor `turn_step` becomes runnable

This keeps compaction in the same workflow graph as the main agent loop.

## Budget Envelope During Prompt Construction

Before prompt construction, Core Matrix should provide a stable budget envelope
through the normal round payload.

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
  - `recommended_input_tokens`
  - `recommended_compaction_threshold`
  - `soft_threshold_tokens`
  - `reserved_tokens`
  - `reserved_output_tokens`
  - `context_soft_limit_ratio`

Meanings:

- `recommended_input_tokens`
  - the prompt-input budget Core Matrix recommends for high-quality dispatch
- `hard_input_token_limit`
  - the largest prompt-input budget Core Matrix believes is dispatchable after
    honoring output reserve
- `reserved_tokens`
  - the total budget intentionally withheld from prompt input
- `reserved_output_tokens`
  - the output-specific portion of that reserve

This envelope is static drafting guidance, not the final preflight decision.

## Agent-Facing Input-Token Counting API

Core Matrix should expose one reusable read-only counting endpoint:

- `POST /agent_api/responses/input_tokens`

This endpoint should:

- be authenticated through the existing AgentAPI surface
- be shaped after OpenAI's `POST /v1/responses/input_tokens`
- accept the same broad class of provider-visible `input` payloads the runtime
  is drafting
- centralize multimodal counting for text, images, file references, and
  audio-bearing inputs

Recommended request fields:

- `provider_handle`
- `model_ref`
- `api_model` when needed
- `input`
- optional candidate metadata for diagnostics

Recommended response fields:

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
- `decision_hint`
- diagnostics

This endpoint is advisory:

- it helps agents that want to draft more carefully
- it never replaces the final dispatch-time guard
- it does not itself create workflow work

## Token Estimation Ownership

Core Matrix owns authoritative token estimation.

Recommended fallback order:

1. exact local tokenizer asset
2. `tiktoken`
3. heuristic estimate

Sophisticated agents are still free to do their own local estimates, but Core
Matrix remains the source of truth for:

- workflow insertion
- dispatch-time allow/consult/reject decisions
- failure classification

## Guard Decision Model

The authoritative dispatch-time guard should return:

- `decision`
- `estimated_tokens`
- `estimator_strategy`
- `failure_scope`
- `retry_mode`
- diagnostics

Decision meanings:

- `allow`
  - dispatch can proceed immediately
- `consult`
  - request still fits, but quality or reserve pressure suggests asking the
    runtime for compaction guidance
- `compact_required`
  - Core Matrix-assisted compaction is required before dispatch
- `reject`
  - dispatch should fail immediately

Immediate rejection applies when the newest selected user input is so large
that compacting older context cannot recover the request within hard limits.

## Consultation Contract

When the guard returns `consult` or `compact_required`, Core Matrix may send a
direct consultation request to the runtime if the current
`request_preparation_contract` advertises consultation support and policy
permits runtime participation.

The consultation request should include:

- the current provider-visible input candidate
- budget diagnostics from the guard
- selected input message `public_id`
- consultation reason
- preservation invariants accumulated so far

The consultation response should include:

- `decision` (`skip`, `compact`, `reject`)
- compaction style guidance
- prioritization hints
- preservation invariants
- diagnostics / rationale

Important boundary:

- the consultation may influence strategy
- it does not itself execute compaction
- it does not mutate workflow state

If runtime consultation is unavailable, Core Matrix may continue with embedded
baseline strategy selection.

## Workflow-Backed Compaction

Once Core Matrix decides to compact, the help must be represented as workflow
work.

Required behavior:

1. Core Matrix materializes a dedicated `prompt_compaction` workflow node
2. the node is scheduled and executed by the workflow engine
3. execution uses:
   - runtime-backed compaction when the runtime capability exists and policy
     allows it
   - embedded compaction otherwise
4. the node persists artifacts and diagnostics
5. the successor `turn_step` consumes the compacted context artifact and
   continues the loop
6. durable transcript history remains unchanged

Core Matrix assistance with compaction must never be an invisible synchronous
side effect.

## Ephemeral Compacted Context Handoff

Compaction in v1 should not rewrite durable transcript history.

Instead, the `prompt_compaction` node should persist an artifact that contains:

- compacted provider-visible messages
- before/after token estimates
- preservation invariants
- source and degradation diagnostics

The successor `turn_step` should consume that artifact as an ephemeral
round-specific override when it rebuilds provider-visible input.

Recommended handoff shape:

- `prompt_compaction` node persists `artifact_kind = "prompt_compaction_context"`
- successor `turn_step` metadata includes:
  - `prompt_compaction_artifact_key`
  - `prompt_compaction_source_node_key`

When a successor `turn_step` sees this metadata, its default transcript source
should come from the compaction artifact rather than directly from
`execution_snapshot.conversation_projection`.

## Baseline Compaction Strategy

The baseline strategy should stand on the patterns we observed in Claude Code,
Codex, and OpenClaw:

- preserve the newest selected user input verbatim
- preserve explicit user constraints and instructions
- preserve active task state and near-term plan
- preserve referenced file paths, resources, and identifiers
- preserve unresolved errors and pending tool outcomes
- compact older transcript before recent task-critical state
- aggressively reduce bulky tool outputs before primary transcript
- stop after bounded attempts with explicit diagnostics

The embedded compactor and Fenix compactor should share this same baseline
contract and the same golden fixtures.

That gives:

- a strong working fallback in Core Matrix
- a quality floor for simple runtimes
- room for Fenix to later evolve a more specialized algorithm without changing
  the minimum contract

## Runtime Vs Embedded Execution

Expected steady state for Fenix:

- runtime consultation available
- runtime workflow-node execution available
- Core Matrix authoritative guard triggers the process

Expected fallback behavior:

- if consultation is unavailable, Core Matrix may use embedded default guidance
- if runtime workflow execution is unavailable or fails and policy allows
  fallback, Core Matrix should run embedded compaction instead
- degraded fallback must be observable through persisted diagnostics

Embedded fallback on Fenix is resilience, not quality equivalence.

## Overflow Recovery

The subsystem should allow one explicit overflow-recovery loop when the
provider still returns a prompt-size overflow:

1. classify the provider error as prompt-size overflow
2. re-enter compaction mode with `consultation_reason = "overflow_recovery"`
3. materialize another compaction workflow node if the result says to compact
4. retry dispatch once

Stop after the hard attempt limit.

No open-ended compaction loops.

## Failure Semantics

Prompt-size failures must be explicit and app-readable.

Recommended failure kinds:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

Persist remediation metadata that tells the app:

- whether the tail input is editable
- whether the user must send a new message
- whether the failure is caused by the current message alone or full context
- selected input message `public_id`
- whether runtime degraded to embedded compaction
- the normalized runtime failure code when degradation happened

These failures should never collapse into `internal_unexpected_error`.

## Observability

The subsystem should persist or emit at least:

- selected model identity
- before/after token estimates
- estimator strategy
- whether runtime consultation occurred
- whether compaction executed via runtime or embedded path
- whether fallback was used
- normalized runtime failure code
- workflow node artifact references

This is especially important on Fenix, where runtime compaction is the intended
quality path.

## Why This Split Is Better

This design is cleaner than forcing prompt compaction through the generic
runtime feature platform:

- the provider request critical path stays explicit
- read-only budgeting and workflow-backed compaction are modeled separately
- agent freedom is preserved
- Core Matrix fallback remains strong
- Core Matrix-assisted compaction is always workflow-visible

## Testing Focus

This subsystem should be tested at five levels:

1. token estimation and budget-envelope calculation
2. agent-facing `responses/input_tokens`
3. guard decisions and consultation triggering
4. workflow-node materialization, execution, and re-entry
5. explicit failure payloads, degradation diagnostics, and deterministic
   tiny-context e2e coverage

## Summary

Prompt compaction should not behave like a generic runtime feature.

It should be implemented as a request-preparation subsystem where:

- agents may remain light or become sophisticated
- Core Matrix owns authoritative budgeting
- Core Matrix-assisted compaction is always workflow-backed
- embedded compaction provides a working fallback
- Fenix can still supply higher-quality consultation and execution
