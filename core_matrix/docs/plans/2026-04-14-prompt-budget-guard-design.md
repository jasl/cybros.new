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
- runtime-first compaction falls back to embedded compaction
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
  - attempt runtime compaction when capability is present
  - fall back to embedded on supported fallback failures
- `runtime_required`
  - require runtime capability and runtime success
  - do not fall back to embedded

## Capability Contract

Fenix manifest should advertise `prompt_compaction` through `feature_contract`,
not `tool_contract`.

The capability entry should include:

- `feature_key = "prompt_compaction"`
- `execution_plane = "agent"`
- `lifecycle = "turn_scoped"`
- input schema for provider messages plus budget context
- result schema for compacted messages plus diagnostics

## Invocation Contract

The runtime request should go through `execute_feature`.

Feature input should contain:

- final provider-visible messages
- hard and advisory budget hints
- model/tokenizer hints
- current selected input message identity
- feature policy snapshot

Feature result should contain:

- replacement messages
- whether compaction changed anything
- optional compaction diagnostics

## Slice-Specific Lifecycle Rules

`prompt_compaction` is execution-critical and must run against the exact turn
state that was frozen before provider dispatch.

That means:

- policy is resolved once and frozen
- capability is resolved once and frozen
- compaction runs against the frozen provider-visible round payload

This feature must not read live workspace policy while a turn is already in
flight.

## Runtime And Embedded Behavior

### Runtime Path

When policy allows runtime execution and the frozen capability snapshot
advertises `prompt_compaction`, the platform should invoke runtime compaction
first.

### Embedded Path

Embedded compaction is required for product resilience.

The embedded executor should:

- preserve the newest selected user input verbatim
- compact older context only
- avoid durable transcript writes
- produce a replacement message list for the current round only

### Runtime Failure Handling

The runtime path should fall back to embedded compaction when strategy permits
and the normalized platform failure is one of:

- `feature_not_advertised`
- `feature_unsupported`
- `feature_timeout`
- `feature_runtime_error`

`runtime_required` should not fall back.

## Guard Integration

`ProviderExecution::ExecuteRoundLoop` should remain the final authority before
provider dispatch.

The slice-specific logic should be:

1. estimate prompt tokens
2. decide `allow`, `compact`, or `reject`
3. invoke `prompt_compaction` through the feature platform when compaction is
   needed
4. retry estimation after compaction
5. dispatch only when the request fits

The feature platform owns compaction execution; the guard owns the dispatch
decision.

## Provider Overflow Recovery

Preflight estimation can still miss.

The slice should allow one bounded recovery loop:

1. provider returns explicit overflow
2. the round re-enters compaction mode
3. `prompt_compaction` runs again
4. provider request retries once

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
2. runtime vs embedded invocation and fallback
3. guard integration and bounded overflow recovery
4. workflow failure payload and user remediation metadata

## Summary

`prompt_compaction` should no longer behave like a special-case internal tool.
It should be implemented as a first-class runtime feature slice:

- snapshot-frozen
- runtime-first
- embedded-backed
- execution-critical
- explicitly recoverable when provider overflow occurs
